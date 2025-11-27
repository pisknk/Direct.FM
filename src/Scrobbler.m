#import "Scrobbler.h"
#include <Foundation/Foundation.h>

// handle ios 8.4.1 mediaremote compatibility
#if __arm__
    // 32-bit ios - use direct framework path
    #import <MediaRemote/MediaRemote.h>
#else
    // 64-bit ios - use private framework
    #import <MediaRemote/MediaRemote.h>
#endif


NSString *md5(NSString *str) {
	const char *cstr = [str UTF8String];
	unsigned char result[CC_MD5_DIGEST_LENGTH];

	CC_MD5(cstr, (int)strlen(cstr), result);
	NSMutableString *result_ns = [[NSMutableString alloc ] init];
	for (int i = 0 ; i < CC_MD5_DIGEST_LENGTH ; i++) [result_ns appendFormat:@"%02x", result[i]];
	return result_ns;
}

NSString *queryString(NSDictionary *items) {
	NSURLComponents *components = [[NSURLComponents alloc] init];
	NSMutableArray <NSURLQueryItem *> *queryItems = [NSMutableArray array];

	for (NSString *key in items.allKeys) {
		[queryItems addObject:[NSURLQueryItem queryItemWithName:key value:items[key]]];
	}

    components.queryItems = queryItems;
	return components.URL.query ?: @"";
}

// clean string by removing common tags and extra information
NSString *cleanString(NSString *input) {
	if (!input || [input length] == 0) return input;
	
	NSMutableString *cleaned = [input mutableCopy];
	
	// remove common patterns (order matters - more specific first)
	NSArray *patternsToRemove = @[
		// video available tags
		@"\\s*•\\s*Video Available",
		@"\\s*•\\s*VIDEO AVAILABLE",
		@"\\s*-\\s*Video Available",
		// explicit tags
		@"\\s*\\[Explicit\\]",
		@"\\s*\\(Explicit\\)",
		@"\\s*-\\s*Explicit",
		// single/ep tags
		@"\\s*\\[Single\\]",
		@"\\s*\\(Single\\)",
		@"\\s*-\\s*Single",
		@"\\s*\\[EP\\]",
		@"\\s*\\(EP\\)",
		@"\\s*-\\s*EP",
		// remaster tags
		@"\\s*\\[Remaster\\w*\\]",
		@"\\s*\\(Remaster\\w*\\)",
		@"\\s*-\\s*Remaster\\w*",
		@"\\s*Remaster\\w*",
		// year patterns (4 digits, with or without parentheses/brackets)
		@"\\s*\\(\\d{4}\\)",
		@"\\s*\\[\\d{4}\\]",
		@"\\s*-\\s*\\d{4}",
		@"\\s+\\d{4}\\b",
		// other common tags
		@"\\s*\\[Deluxe\\]",
		@"\\s*\\(Deluxe\\)",
		@"\\s*-\\s*Deluxe",
		@"\\s*\\[Extended\\]",
		@"\\s*\\(Extended\\)",
		@"\\s*-\\s*Extended",
		@"\\s*\\[Bonus Track\\]",
		@"\\s*\\(Bonus Track\\)",
		@"\\s*-\\s*Bonus Track",
		@"\\s*\\[Live\\]",
		@"\\s*\\(Live\\)",
		@"\\s*-\\s*Live",
		@"\\s*\\[Acoustic\\]",
		@"\\s*\\(Acoustic\\)",
		@"\\s*-\\s*Acoustic",
	];
	
	// apply each pattern (recalculate range after each replacement since string length changes)
	for (NSString *pattern in patternsToRemove) {
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
		if (regex) {
			// keep replacing until no more matches found
			NSUInteger replacements = 0;
			do {
				NSRange range = NSMakeRange(0, [cleaned length]);
				replacements = [regex replaceMatchesInString:cleaned options:0 range:range withTemplate:@""];
			} while (replacements > 0);
		}
	}
	
	// trim whitespace
	cleaned = [[cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] mutableCopy];
	
	// remove trailing separators (•, -, etc.)
	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@"•-–—"];
	while ([cleaned length] > 0 && [separators characterIsMember:[cleaned characterAtIndex:[cleaned length] - 1]]) {
		[cleaned deleteCharactersInRange:NSMakeRange([cleaned length] - 1, 1)];
		cleaned = [[cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] mutableCopy];
	}
	
	return [cleaned copy];
}

@implementation Scrobbler

// cache file path helper
-(NSString*) cacheFilePath {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
	return [documentsDirectory stringByAppendingPathComponent:@"DirectFMScrobbleCache.plist"];
}

// scrobble history file path helper
-(NSString*) historyFilePath {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
	return [documentsDirectory stringByAppendingPathComponent:@"DirectFMScrobbleHistory.plist"];
}

// load cached scrobbles from disk
-(NSMutableArray*) loadCachedScrobbles {
	NSString *filePath = [self cacheFilePath];
	if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
		NSArray *cached = [NSArray arrayWithContentsOfFile:filePath];
		if (cached) {
			return [cached mutableCopy];
		}
	}
	return [[NSMutableArray alloc] init];
}

// save cached scrobbles to disk
-(void) saveCachedScrobbles:(NSArray*)scrobbles {
	NSString *filePath = [self cacheFilePath];
	[scrobbles writeToFile:filePath atomically:YES];
	
	// update cache count in preferences
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_BUNDLE_ID];
	[defaults setInteger:[scrobbles count] forKey:@"cachedScrobblesCount"];
	[defaults synchronize];
}

// add scrobble to cache
-(void) cacheScrobble:(NSDictionary*)scrobbleData {
	NSMutableArray *cached = [self loadCachedScrobbles];
	[cached addObject:scrobbleData];
	[self saveCachedScrobbles:cached];
	NSLog(@"[Direct.FM] Cached scrobble: %@ - %@ (total cached: %lu)", scrobbleData[@"artist[0]"], scrobbleData[@"track[0]"], (unsigned long)[cached count]);
}

// get count of cached scrobbles
-(NSInteger) getCachedScrobblesCount {
	NSArray *cached = [self loadCachedScrobbles];
	return [cached count];
}

// save scrobble to history
-(void) saveScrobbleToHistory:(NSString*)track artist:(NSString*)artist album:(NSString*)album timestamp:(NSString*)timestamp {
	NSMutableArray *history = [[self loadScrobbleHistory] mutableCopy];
	
	NSDictionary *scrobbleEntry = @{
		@"track": track ?: @"",
		@"artist": artist ?: @"",
		@"album": album ?: @"",
		@"timestamp": timestamp ?: @"",
		@"date": [[NSDate date] description]
	};
	
	[history insertObject:scrobbleEntry atIndex:0]; // add to beginning
	
	// limit history to last 1000 scrobbles
	if ([history count] > 1000) {
		[history removeObjectsInRange:NSMakeRange(1000, [history count] - 1000)];
	}
	
	NSString *filePath = [self historyFilePath];
	[history writeToFile:filePath atomically:YES];
}

// load scrobble history
-(NSArray*) loadScrobbleHistory {
	NSString *filePath = [self historyFilePath];
	if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
		NSArray *history = [NSArray arrayWithContentsOfFile:filePath];
		if (history) {
			return history;
		}
	}
	return [[NSArray alloc] init];
}

// unscrobble a track from last.fm
-(void) unscrobbleTrack:(NSString*)track artist:(NSString*)artist timestamp:(NSString*)timestamp completionHandler:(void(^)(BOOL success, NSError *error))completionHandler {
	NSMutableDictionary *dict = [@{
		@"track": track,
		@"artist": artist,
		@"timestamp": timestamp,
		@"method": @"track.unscrobble"
	} mutableCopy];
	
	[self requestLastfm:dict completionHandler:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
		BOOL success = NO;
		if (!error && response && response.statusCode == 200) {
			success = YES;
			NSLog(@"[Direct.FM] Unscrobbled track: %@ - %@", artist, track);
			
			// remove from history
			NSMutableArray *history = [[self loadScrobbleHistory] mutableCopy];
			NSMutableArray *toRemove = [[NSMutableArray alloc] init];
			for (NSDictionary *entry in history) {
				if ([[entry objectForKey:@"track"] isEqualToString:track] && 
					[[entry objectForKey:@"artist"] isEqualToString:artist] &&
					[[entry objectForKey:@"timestamp"] isEqualToString:timestamp]) {
					[toRemove addObject:entry];
				}
			}
			[history removeObjectsInArray:toRemove];
			
			NSString *filePath = [self historyFilePath];
			[history writeToFile:filePath atomically:YES];
			
			// update count
			NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_BUNDLE_ID];
			NSInteger currentCount = [defaults integerForKey:@"scrobbleCount"];
			if (currentCount > 0) {
				[defaults setInteger:currentCount - [toRemove count] forKey:@"scrobbleCount"];
				[defaults synchronize];
			}
		} else {
			NSLog(@"[Direct.FM] Failed to unscrobble track: %@ - %@, Error: %@", artist, track, error);
		}
		
		if (completionHandler) {
			completionHandler(success, error);
		}
	}];
}

// check if network is available
-(BOOL) isNetworkAvailable {
	// use reachability or simple connectivity check
	// for simplicity, we'll assume network is available if we can create a session
	// the actual request will fail gracefully if network is unavailable
	return YES; // let the actual request determine connectivity
}

// helper method to process a single scrobble at index (avoids retain cycle)
-(void) processCachedScrobbleAtIndex:(NSInteger)index 
                            fromCache:(NSArray*)cached 
                      failedScrobbles:(NSMutableArray*)failedScrobbles 
                         successCount:(NSInteger*)successCount 
                            onQueue:(dispatch_queue_t)queue {
	if (index >= [cached count]) {
		// all done - save results
		[self saveCachedScrobbles:failedScrobbles];
		
		// update status
		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_BUNDLE_ID];
		NSString *status = [NSString stringWithFormat:@"Retried %ld scrobbles, %ld succeeded, %ld failed", (long)[cached count], (long)*successCount, (long)[failedScrobbles count]];
		[defaults setObject:status forKey:@"lastCacheRetryStatus"];
		[defaults synchronize];
		
		NSLog(@"[Direct.FM] Cache retry complete: %@", status);
		return;
	}
	
	NSDictionary *scrobbleData = cached[index];
	NSMutableDictionary *params = [scrobbleData mutableCopy];
	
	[self requestLastfm:params completionHandler:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
		dispatch_async(queue, ^{
			if (error || !response || response.statusCode != 200) {
				[failedScrobbles addObject:scrobbleData];
				NSLog(@"[Direct.FM] Failed to retry cached scrobble: %@ - %@", scrobbleData[@"artist[0]"], scrobbleData[@"track[0]"]);
			} else {
				(*successCount)++;
				NSLog(@"[Direct.FM] Successfully retried cached scrobble: %@ - %@", scrobbleData[@"artist[0]"], scrobbleData[@"track[0]"]);
			}
			
			// small delay between requests to avoid rate limiting, then process next
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), queue, ^{
				[self processCachedScrobbleAtIndex:index + 1 
				                          fromCache:cached 
				                    failedScrobbles:failedScrobbles 
				                       successCount:successCount 
				                          onQueue:queue];
			});
		});
	}];
}

// retry cached scrobbles
-(void) retryCachedScrobbles {
	NSMutableArray *cached = [self loadCachedScrobbles];
	if ([cached count] == 0) {
		NSLog(@"[Direct.FM] No cached scrobbles to retry");
		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_BUNDLE_ID];
		[defaults setObject:@"No cached scrobbles" forKey:@"lastCacheRetryStatus"];
		[defaults synchronize];
		return;
	}
	
	NSLog(@"[Direct.FM] Retrying %lu cached scrobbles...", (unsigned long)[cached count]);
	
	NSMutableArray *failedScrobbles = [[NSMutableArray alloc] init];
	__block NSInteger successCount = 0;
	
	// process scrobbles sequentially to avoid rate limiting
	dispatch_queue_t retryQueue = dispatch_queue_create("com.directfm.retry", DISPATCH_QUEUE_SERIAL);
	
	// start processing from index 0
	dispatch_async(retryQueue, ^{
		[self processCachedScrobbleAtIndex:0 
		                          fromCache:cached 
		                    failedScrobbles:failedScrobbles 
		                       successCount:&successCount 
		                          onQueue:retryQueue];
	});
}

-(void) requestLastfm:(NSMutableDictionary*)params completionHandler:(void(^)(NSData *data, NSHTTPURLResponse *response, NSError *error))completionHandler {
    NSMutableString *sigRaw = [[NSMutableString alloc] init];
    NSMutableString *payload = [[NSMutableString alloc] init];

	[params setValue:self.token forKey:@"sk"];
	[params setValue:self.apiKey forKey:@"api_key"];

    NSArray *keys = [[params allKeys] sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *key in keys) {
        NSString *value = [params objectForKey:key];
        [sigRaw appendFormat:@"%@%@", key, value];
    }
	
	[payload appendString:queryString(params)];

	[sigRaw appendString:self.apiSecret]; 

    [payload appendFormat:@"&api_sig=%@", md5(sigRaw)];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://ws.audioscrobbler.com/2.0/"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setHTTPBody:[payload dataUsingEncoding:NSUTF8StringEncoding]];

	NSURLSession *session = [NSURLSession sharedSession];
	NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
		completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *resp = (NSHTTPURLResponse*)response;
        	if (resp.statusCode == 403) {
				[self tokenExpired];
				completionHandler(data, resp, error);
			} else if (resp.statusCode != 200) {
				NSLog(@"[Direct.FM] An unknown error occured: Status code = %ld, data = %@", (long)resp.statusCode, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
				completionHandler(data, resp, error);
			} else if (error) {
				// network error - cache if it's a scrobble
				NSString *method = [params objectForKey:@"method"];
				if ([method isEqualToString:@"track.scrobble"]) {
					NSLog(@"[Direct.FM] Network error during scrobble, caching: %@", error);
					[self cacheScrobble:params];
				}
				completionHandler(data, resp, error);
			} else {
				completionHandler(data, resp, error);
			}
		}];
	[dataTask resume];
}

-(void) updateNowPlaying:(NSString*)music withArtist:(NSString*)artist album:(NSString*)album {
	// check if tag cleaning is enabled
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
	BOOL removeTags = [defaults objectForKey:@"removeExtraTags"] ? [[defaults objectForKey:@"removeExtraTags"] boolValue] : YES;
	
	// clean strings if enabled
	NSString *cleanedTrack = removeTags ? cleanString(music) : music;
	NSString *cleanedArtist = removeTags ? cleanString(artist) : artist;
	NSString *cleanedAlbum = removeTags ? cleanString(album) : album;
	
	// log if cleaning changed anything
	if (removeTags && (![cleanedTrack isEqualToString:music] || ![cleanedArtist isEqualToString:artist] || ![cleanedAlbum isEqualToString:album])) {
		NSLog(@"[Direct.FM] Cleaned tags - Track: \"%@\" -> \"%@\", Artist: \"%@\" -> \"%@\", Album: \"%@\" -> \"%@\"", music, cleanedTrack, artist, cleanedArtist, album, cleanedAlbum);
	}
	
	NSMutableDictionary *dict = [@{
		@"track": cleanedTrack,
		@"artist": cleanedArtist,
		@"album": cleanedAlbum,
		@"method": @"track.updateNowPlaying",
	} mutableCopy];

	// check if logged in before updating now playing
	if (!self.loggedIn || !self.token) {
		NSLog(@"[Direct.FM] updateNowPlaying: Not logged in (loggedIn: %d, token: %@), cannot update now playing", self.loggedIn, self.token ? @"exists" : @"nil");
		return;
	}
	
	[self requestLastfm:dict completionHandler:^(NSData *data, NSHTTPURLResponse *response, NSError *error){
		if (error) {
			NSLog(@"[Direct.FM] Failed to update now playing: %@ - Error: %@", cleanedTrack, error);
		} else if (!response) {
			NSLog(@"[Direct.FM] Failed to update now playing: %@ - No response", cleanedTrack);
		} else if (response.statusCode != 200) {
			NSString *responseData = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"No data";
			NSLog(@"[Direct.FM] Failed to update now playing: %@ - Status: %ld, Response: %@", cleanedTrack, (long)response.statusCode, responseData);
		} else {
			NSLog(@"[Direct.FM] Successfully updated now playing track to %@", cleanedTrack);
		}
	}];
} 

-(void) scrobbleTrack:(NSString*)music withArtist:(NSString*)artist album:(NSString*)album atTimestamp:(NSString*)timestamp {
	// check if logged in
	if (!self.loggedIn || !self.token) {
		NSLog(@"[Direct.FM] scrobbleTrack: Not logged in (loggedIn: %d, token: %@), caching scrobble", self.loggedIn, self.token ? @"exists" : @"nil");
		NSMutableDictionary *dict = [@{
			@"track[0]": music ?: @"",
			@"artist[0]": artist ?: @"",
			@"album[0]": album ?: @"",
			@"timestamp[0]": timestamp ?: @"",
			@"method": @"track.scrobble"
		} mutableCopy];
		[self cacheScrobble:dict];
		return;
	}
	
	// check if tag cleaning is enabled
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
	BOOL removeTags = [defaults objectForKey:@"removeExtraTags"] ? [[defaults objectForKey:@"removeExtraTags"] boolValue] : YES;
	
	// clean strings if enabled
	NSString *cleanedTrack = removeTags ? cleanString(music) : music;
	NSString *cleanedArtist = removeTags ? cleanString(artist) : artist;
	NSString *cleanedAlbum = removeTags ? cleanString(album) : album;
	
	// log if cleaning changed anything
	if (removeTags && (![cleanedTrack isEqualToString:music] || ![cleanedArtist isEqualToString:artist] || ![cleanedAlbum isEqualToString:album])) {
		NSLog(@"[Direct.FM] Cleaned tags before scrobbling - Track: \"%@\" -> \"%@\", Artist: \"%@\" -> \"%@\", Album: \"%@\" -> \"%@\"", music, cleanedTrack, artist, cleanedArtist, album, cleanedAlbum);
	}
	
	NSLog(@"[Direct.FM] scrobbleTrack: Attempting to scrobble - Track: %@, Artist: %@, Album: %@, Timestamp: %@", cleanedTrack, cleanedArtist, cleanedAlbum, timestamp);
	
	NSMutableDictionary *dict = [@{
		@"track[0]": cleanedTrack,
		@"artist[0]": cleanedArtist,
		@"album[0]": cleanedAlbum,
		@"timestamp[0]": timestamp,
		@"method": @"track.scrobble"
	} mutableCopy];

	[self requestLastfm:dict completionHandler:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
		if (error) {
			// network error - cache the scrobble
			NSLog(@"[Direct.FM] Failed to scrobble track %@ due to network error, caching for retry. Error: %@", cleanedTrack, error);
			[self cacheScrobble:dict];
		} else if (!response) {
			// no response - cache the scrobble
			NSLog(@"[Direct.FM] Failed to scrobble track %@ - no response received, caching for retry", cleanedTrack);
			[self cacheScrobble:dict];
		} else if (response.statusCode != 200) {
			// non-200 status - log and cache
			NSString *responseData = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"No data";
			NSLog(@"[Direct.FM] Failed to scrobble track %@ - HTTP status: %ld, Response: %@", cleanedTrack, (long)response.statusCode, responseData);
			[self cacheScrobble:dict];
		} else {
			// success!
			NSLog(@"[Direct.FM] Successfully scrobbled track %@ by %@", cleanedTrack, cleanedArtist);
			
			// save to history
			[self saveScrobbleToHistory:cleanedTrack artist:cleanedArtist album:cleanedAlbum timestamp:timestamp];
			
			// Update debug information
			NSInteger currentCount = [defaults integerForKey:@"scrobbleCount"];
			[defaults setInteger:currentCount + 1 forKey:@"scrobbleCount"];
			[defaults setObject:[NSString stringWithFormat:@"%@ - %@", cleanedArtist, cleanedTrack] forKey:@"lastScrobbledTrack"];
			[defaults synchronize];
		}
	}];
}

-(void) tokenExpired {
    self.loggedIn = false;
    self.token = nil;
    [self deleteToken];
    dispatch_async(dispatch_get_main_queue(), ^(void){
        NSLog(@"[Direct.FM] Reloading token");
        [self loadToken];
    });
}

-(void) loadToken {
	if ([self loadTokenFromKeychain]) return;
	NSLog(@"[Direct.FM] Authenticating with last.fm...");

    NSString *sigContent = [NSString stringWithFormat:@"api_key%@method%@password%@username%@%@", self.apiKey, @"auth.getMobileSession", self.password, self.username, self.apiSecret];
	NSString *sig = md5(sigContent);

	NSString *query = queryString(@{@"method": @"auth.getMobileSession", @"username": self.username, @"password": self.password, @"api_key": self.apiKey, @"api_sig": sig, @"format": @"json"});

	NSURL *url = [NSURL URLWithString:@"https://ws.audioscrobbler.com/2.0/"];

	NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:url];
	[req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [req setHTTPBody:[query dataUsingEncoding:NSUTF8StringEncoding]];

	[[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
		if ([resp statusCode] != 200) {
			NSLog(@"Failed to login!");
			return;
		}
		// parse response
		NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		self.token = [[dict valueForKey:@"session"] valueForKey:@"key"];
		self.loggedIn = true;
		[self syncKeychain];
        [self registerObserver];
	}] resume];
}

-(void) getCurrentlyPlayingMusicWithcompletionHandler:(void(^)(NSString *track, NSString *artist, NSString *album, NSDate *date, NSNumber *duration))completionHandler {
	MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
		if (!info) {
			NSLog(@"[Direct.FM] getCurrentlyPlayingMusicWithcompletionHandler: info is nil");
			return;
		}
		NSDictionary *dict = (__bridge NSDictionary*)info;
		if (!dict) {
			NSLog(@"[Direct.FM] getCurrentlyPlayingMusicWithcompletionHandler: dict is nil");
			return;
		}
		
		id musicObj = [dict objectForKey:@"kMRMediaRemoteNowPlayingInfoTitle"];
		id artistObj = [dict objectForKey:@"kMRMediaRemoteNowPlayingInfoArtist"];
		id albumObj = [dict objectForKey:@"kMRMediaRemoteNowPlayingInfoAlbum"];
		id dateObj = [dict valueForKey:@"kMRMediaRemoteNowPlayingInfoTimestamp"];
		id durationObj = [dict valueForKey:@"kMRMediaRemoteNowPlayingInfoDuration"];
		
		NSString *music = ([musicObj isKindOfClass:[NSString class]]) ? musicObj : nil;
		NSString *artist = ([artistObj isKindOfClass:[NSString class]]) ? artistObj : nil;
		NSString *album = ([albumObj isKindOfClass:[NSString class]]) ? albumObj : nil;
		NSDate *date = ([dateObj isKindOfClass:[NSDate class]]) ? dateObj : nil;
		NSNumber *duration = ([durationObj isKindOfClass:[NSNumber class]]) ? durationObj : nil;
		
		if (!artist || !album || !music) {
			NSLog(@"[Direct.FM] getCurrentlyPlayingMusicWithcompletionHandler: missing required fields - track: %@, artist: %@, album: %@", music, artist, album);
			return;
		}

		completionHandler(music, artist, album, date, duration);
	}); 
}

-(void) registerObserver {
    // use bridge cast for CFStringRef to NSNotificationName conversion
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(musicDidChange:) name:(__bridge NSNotificationName)kMRMediaRemoteNowPlayingInfoDidChangeNotification object:nil];
	MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());
}

-(void) musicDidChange:(NSNotification*)notification {
	@try {
		if (!notification) {
			NSLog(@"[Direct.FM] musicDidChange: notification is nil");
			return;
		}
		
		NSDictionary *userInfo = [notification userInfo];
		if (!userInfo) {
			NSLog(@"[Direct.FM] musicDidChange: userInfo is nil");
			return;
		}
		
		// safely check originating notification
		id originatingNotification = [userInfo objectForKey:@"_MROriginatingNotification"];
		if (!originatingNotification || ![originatingNotification isKindOfClass:[NSString class]]) {
			NSLog(@"[Direct.FM] musicDidChange: invalid or missing _MROriginatingNotification");
			return;
		}
		
		if (![originatingNotification isEqualToString:@"_kMRNowPlayingPlaybackQueueChangedNotification"]) {
			NSLog(@"[Direct.FM] musicDidChange: ignoring notification type: %@", originatingNotification);
			return;
		}
		
		// extract bundle identifier from notification
		id clientInfo = [userInfo objectForKey:@"kMRNowPlayingClientUserInfoKey"];
		NSString *appBID = nil;
		
		if (clientInfo && [clientInfo respondsToSelector:@selector(bundleIdentifier)]) {
			@try {
				appBID = [clientInfo bundleIdentifier];
				if (![appBID isKindOfClass:[NSString class]]) {
					appBID = nil;
				}
			} @catch (NSException *exception) {
				NSLog(@"[Direct.FM] musicDidChange: exception getting bundleIdentifier: %@", exception);
				appBID = nil;
			}
		}
		
		// fallback: try to get from userInfo directly if available
		if (!appBID || [appBID length] == 0) {
			id bidObj = [userInfo objectForKey:@"kMRMediaRemoteNowPlayingInfoApplicationBundleIdentifier"];
			if ([bidObj isKindOfClass:[NSString class]]) {
				appBID = bidObj;
			}
		}
		
		// if still no bundle ID, log and return
		if (!appBID || [appBID length] == 0) {
			NSLog(@"[Direct.FM] Could not extract bundle identifier from notification: %@", userInfo);
			return;
		}
		
		// Update current playing app debug info
		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
		NSString *appName = @"Unknown";
		if ([appBID isEqualToString:@"com.apple.Music"]) appName = @"Apple Music";
		else if ([appBID isEqualToString:@"com.spotify.client"]) appName = @"Spotify";
		else if ([appBID isEqualToString:@"com.google.ios.youtubemusic"]) appName = @"YouTube Music";
		else if ([appBID isEqualToString:@"com.google.ios.youtube"]) appName = @"YouTube";
		else appName = [NSString stringWithFormat:@"Other (%@)", appBID];
		
		[defaults setObject:appName forKey:@"currentPlayingApp"];
		[defaults synchronize];
		
		NSLog(@"[Direct.FM] Music changed from app: %@ (%@)", appName, appBID);
		NSLog(@"[Direct.FM] Selected apps: %@", self.selectedApps);
		NSLog(@"[Direct.FM] Selected apps count: %lu", (unsigned long)[self.selectedApps count]);
		
		// check if app is in selected apps list
		if (!self.selectedApps || [self.selectedApps count] == 0) {
			NSLog(@"[Direct.FM] No apps selected, ignoring");
			return;
		}
		
		if (![self.selectedApps containsObject:appBID]) {
			NSLog(@"[Direct.FM] App %@ (%@) not in selected apps list, ignoring", appName, appBID);
			NSLog(@"[Direct.FM] Available selected apps: %@", self.selectedApps);
			return;
		}
		
		NSLog(@"[Direct.FM] App %@ (%@) is in selected apps, proceeding with scrobble", appName, appBID);

		[self getCurrentlyPlayingMusicWithcompletionHandler:^(NSString *track, NSString *artist, NSString *album, NSDate *date, NSNumber *duration){
			// only require track and artist - album is optional
			if (!track || !artist) {
				NSLog(@"[Direct.FM] musicDidChange: missing required track info - track: %@, artist: %@, album: %@", track, artist, album ?: @"(nil)");
				return;
			}
			
			// use empty string if album is nil
			if (!album) {
				album = @"";
			}
			
			NSLog(@"[Direct.FM] musicDidChange: Got track info - Track: %@, Artist: %@, Album: %@, Duration: %@", track, artist, album, duration);
			NSLog(@"[Direct.FM] musicDidChange: Login status - loggedIn: %d, token: %@", self.loggedIn, self.token ? @"exists" : @"nil");
			
			// always try to update now playing (will fail gracefully if not logged in)
			[self updateNowPlaying:track withArtist:artist album:album];
			
			// only proceed with scrobble scheduling if logged in
			if (!self.loggedIn || !self.token) {
				NSLog(@"[Direct.FM] musicDidChange: Not logged in, skipping scrobble scheduling");
				return;
			}

			// only schedule scrobble if we have valid duration
			if (duration && [duration isKindOfClass:[NSNumber class]]) {
				double durationValue = [duration doubleValue];
				NSLog(@"[Direct.FM] musicDidChange: Duration value: %f, scrobbleAfter: %f", durationValue, self.scrobbleAfter);
				
				if (durationValue > 0) {
					double delaySeconds = durationValue * self.scrobbleAfter;
					NSLog(@"[Direct.FM] musicDidChange: Scheduling scrobble in %.1f seconds (%.1f%% of %.1f seconds)", delaySeconds, self.scrobbleAfter * 100, durationValue);
					
					if (delaySeconds > 0 && delaySeconds < 3600) { // sanity check: max 1 hour
						dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
							NSLog(@"[Direct.FM] musicDidChange: Delay completed, checking if track is still playing...");
							[self getCurrentlyPlayingMusicWithcompletionHandler:^(NSString *currentTrack, NSString *currentArtist, NSString *currentAlbum, NSDate *currentDate, NSNumber *currentDuration){
								// only require track and artist - album is optional
								if (!currentTrack || !currentArtist) {
									NSLog(@"[Direct.FM] musicDidChange: missing current track info for scrobble check - track: %@, artist: %@, album: %@", currentTrack, currentArtist, currentAlbum ?: @"(nil)");
									return;
								}
								
								// use empty string if album is nil
								if (!currentAlbum) {
									currentAlbum = @"";
								}
								
							NSLog(@"[Direct.FM] musicDidChange: Current track - Track: %@, Artist: %@, Album: %@", currentTrack, currentArtist, currentAlbum);
							NSLog(@"[Direct.FM] musicDidChange: Original track - Track: %@, Artist: %@, Album: %@", track, artist, album);
							
							// clean both tracks for comparison (in case cleaning settings changed)
							NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
							BOOL removeTags = [defaults objectForKey:@"removeExtraTags"] ? [[defaults objectForKey:@"removeExtraTags"] boolValue] : YES;
							
							NSString *cleanedCurrentTrack = removeTags ? cleanString(currentTrack) : currentTrack;
							NSString *cleanedCurrentArtist = removeTags ? cleanString(currentArtist) : currentArtist;
							NSString *cleanedCurrentAlbum = removeTags ? cleanString(currentAlbum) : currentAlbum;
							
							NSString *cleanedOriginalTrack = removeTags ? cleanString(track) : track;
							NSString *cleanedOriginalArtist = removeTags ? cleanString(artist) : artist;
							NSString *cleanedOriginalAlbum = removeTags ? cleanString(album) : album;
							
							// trim whitespace for comparison
							cleanedCurrentTrack = [cleanedCurrentTrack stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
							cleanedCurrentArtist = [cleanedCurrentArtist stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
							cleanedOriginalTrack = [cleanedOriginalTrack stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
							cleanedOriginalArtist = [cleanedOriginalArtist stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
							
							// use case-insensitive comparison for track/artist matching
							// album is optional - we only require track and artist to match
							BOOL tracksMatch = [cleanedCurrentTrack caseInsensitiveCompare:cleanedOriginalTrack] == NSOrderedSame;
							BOOL artistsMatch = [cleanedCurrentArtist caseInsensitiveCompare:cleanedOriginalArtist] == NSOrderedSame;
							
							NSLog(@"[Direct.FM] musicDidChange: Comparison - Original: '%@' by '%@' vs Current: '%@' by '%@'", cleanedOriginalTrack, cleanedOriginalArtist, cleanedCurrentTrack, cleanedCurrentArtist);
							NSLog(@"[Direct.FM] musicDidChange: Match results - Track: %d, Artist: %d", tracksMatch, artistsMatch);
								
							if (!tracksMatch || !artistsMatch) {
								NSLog(@"[Direct.FM] musicDidChange: track changed before scrobble, skipping");
								return;
							}
							
							NSLog(@"[Direct.FM] musicDidChange: Track still playing, proceeding with scrobble");
							
							// safely get timestamp
							double timestamp = 0;
							if (date && [date isKindOfClass:[NSDate class]]) {
								timestamp = [date timeIntervalSince1970];
							} else {
								timestamp = [[NSDate date] timeIntervalSince1970];
							}
							
							NSLog(@"[Direct.FM] musicDidChange: About to call scrobbleTrack - Track: %@, Artist: %@, Album: %@, Timestamp: %.0f", track, artist, album, timestamp);
							NSLog(@"[Direct.FM] musicDidChange: Login status before scrobble - loggedIn: %d, token: %@", self.loggedIn, self.token ? @"exists" : @"nil");
							
							// call scrobble on main queue
							dispatch_async(dispatch_get_main_queue(), ^{
								[self scrobbleTrack:track withArtist:artist album:album atTimestamp:[NSString stringWithFormat:@"%f", timestamp]];
							});
							}];
						});
					} else {
						NSLog(@"[Direct.FM] musicDidChange: delaySeconds out of range: %.1f (must be 0-3600)", delaySeconds);
					}
				} else {
					NSLog(@"[Direct.FM] musicDidChange: duration is 0 or negative: %f", durationValue);
					// if duration is 0 or invalid, scrobble immediately after a short delay
					NSLog(@"[Direct.FM] musicDidChange: No duration available, scrobbling immediately after 5 seconds");
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
						double timestamp = 0;
						if (date && [date isKindOfClass:[NSDate class]]) {
							timestamp = [date timeIntervalSince1970];
						} else {
							timestamp = [[NSDate date] timeIntervalSince1970];
						}
						NSLog(@"[Direct.FM] musicDidChange: Scrobbling track immediately (no duration) - %@ by %@", track, artist);
						[self scrobbleTrack:track withArtist:artist album:album atTimestamp:[NSString stringWithFormat:@"%f", timestamp]];
					});
				}
			} else {
				NSLog(@"[Direct.FM] musicDidChange: no valid duration object, scrobbling immediately after 5 seconds");
				// if no duration, scrobble after a short delay
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
					double timestamp = 0;
					if (date && [date isKindOfClass:[NSDate class]]) {
						timestamp = [date timeIntervalSince1970];
					} else {
						timestamp = [[NSDate date] timeIntervalSince1970];
					}
					NSLog(@"[Direct.FM] musicDidChange: Scrobbling track immediately (no duration object) - %@ by %@", track, artist);
					[self scrobbleTrack:track withArtist:artist album:album atTimestamp:[NSString stringWithFormat:@"%f", timestamp]];
				});
			}
		}];
	} @catch (NSException *exception) {
		NSLog(@"[Direct.FM] musicDidChange: CRITICAL EXCEPTION - %@: %@", [exception name], [exception reason]);
		NSLog(@"[Direct.FM] musicDidChange: stack trace: %@", [exception callStackSymbols]);
	}
}

-(void) deleteToken {
    NSDictionary *req = @ { 
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, 
		(__bridge id)kSecAttrAccount: @"token", 
		(__bridge id)kSecAttrService: BUNDLE_ID, 
	};
	SecItemDelete((__bridge CFDictionaryRef)req);
}

-(void)syncKeychain {
	NSDictionary *req = @ { 
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, 
		(__bridge id)kSecAttrAccount: @"token", 
		(__bridge id)kSecAttrService: BUNDLE_ID, 
		(__bridge id)kSecValueData: [self.token dataUsingEncoding:NSUTF8StringEncoding],
		(__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
	};
	SecItemDelete((__bridge CFDictionaryRef)req);
	SecItemAdd((__bridge CFDictionaryRef)req, NULL);
}

-(bool) loadTokenFromKeychain {
	NSDictionary *req = @ { 
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, 
		(__bridge id)kSecAttrAccount: @"token", 
		(__bridge id)kSecAttrService: BUNDLE_ID,
		(__bridge id)kSecReturnData: @YES,
	};
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)req, &result);
	if (status == errSecSuccess && result != NULL) {
		self.token = [[NSString alloc] initWithData:(__bridge NSData*)result encoding:NSUTF8StringEncoding];
		self.loggedIn = true; // set logged in flag when token is loaded
        [self registerObserver];
		NSLog(@"[Direct.FM] Found token in keychain! Logged in: %d", self.loggedIn);

		CFRelease(result);

		return true;
	}
	return false;
}

@end