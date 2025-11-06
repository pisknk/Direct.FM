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
        	if (resp.statusCode == 403) [self tokenExpired];
			else if (resp.statusCode != 200) NSLog(@"[Direct.FM] An unknown error occured: Status code = %ld, data = %@", (long)resp.statusCode, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
			else completionHandler(data, resp, error);
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

	[self requestLastfm:dict completionHandler:^(NSData *data, NSHTTPURLResponse *response, NSError *error){
		NSLog(@"[Direct.FM] Updated now playing track to %@", cleanedTrack);
	}];
} 

-(void) scrobbleTrack:(NSString*)music withArtist:(NSString*)artist album:(NSString*)album atTimestamp:(NSString*)timestamp {
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
	
	NSMutableDictionary *dict = [@{
		@"track[0]": cleanedTrack,
		@"artist[0]": cleanedArtist,
		@"album[0]": cleanedAlbum,
		@"timestamp[0]": timestamp,
		@"method": @"track.scrobble"
	} mutableCopy];

	[self requestLastfm:dict completionHandler:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
		NSLog(@"[Direct.FM] Scrobbled track %@", cleanedTrack);
		
		// Update debug information
		NSInteger currentCount = [defaults integerForKey:@"scrobbleCount"];
		[defaults setInteger:currentCount + 1 forKey:@"scrobbleCount"];
		[defaults setObject:[NSString stringWithFormat:@"%@ - %@", cleanedArtist, cleanedTrack] forKey:@"lastScrobbledTrack"];
		[defaults synchronize];
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
		if (!info) return;
		NSDictionary *dict = (__bridge NSDictionary*)info;
		NSString *music = (NSString*)[dict objectForKey:@"kMRMediaRemoteNowPlayingInfoTitle"];
		NSString *artist = (NSString*)[dict objectForKey:@"kMRMediaRemoteNowPlayingInfoArtist"];
		NSString *album = (NSString*)[dict objectForKey:@"kMRMediaRemoteNowPlayingInfoAlbum"];
		NSDate *date = [dict valueForKey:@"kMRMediaRemoteNowPlayingInfoTimestamp"];
		NSNumber *duration = [dict valueForKey:@"kMRMediaRemoteNowPlayingInfoDuration"];
		if (!artist || !album || !music) return;

		completionHandler(music, artist, album, date, duration);
	}); 
}

-(void) registerObserver {
    // use bridge cast for CFStringRef to NSNotificationName conversion
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(musicDidChange:) name:(__bridge NSNotificationName)kMRMediaRemoteNowPlayingInfoDidChangeNotification object:nil];
	MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());
}

-(void) musicDidChange:(NSNotification*)notification {
	if (![[[notification userInfo] objectForKey:@"_MROriginatingNotification"] isEqualToString:@"_kMRNowPlayingPlaybackQueueChangedNotification"]) return;
	
	// extract bundle identifier from notification
	id clientInfo = [[notification userInfo] objectForKey:@"kMRNowPlayingClientUserInfoKey"];
	NSString *appBID = nil;
	
	if (clientInfo && [clientInfo respondsToSelector:@selector(bundleIdentifier)]) {
		appBID = [clientInfo bundleIdentifier];
	}
	
	// fallback: try to get from userInfo directly if available
	if (!appBID) {
		appBID = [[notification userInfo] objectForKey:@"kMRMediaRemoteNowPlayingInfoApplicationBundleIdentifier"];
	}
	
	// if still no bundle ID, log and return
	if (!appBID || [appBID length] == 0) {
		NSLog(@"[Direct.FM] Could not extract bundle identifier from notification: %@", [notification userInfo]);
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
		[self updateNowPlaying:track withArtist:artist album:album];

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([duration intValue] * self.scrobbleAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[self getCurrentlyPlayingMusicWithcompletionHandler:^(NSString *currentTrack, NSString *currentArtist, NSString *currentAlbum, NSDate *currentDate, NSNumber *currentDuration){
				if (![currentTrack isEqualToString:track] || ![currentAlbum isEqualToString:album] || ![currentArtist isEqualToString:artist]) return;
				[self scrobbleTrack:track withArtist:artist album:album atTimestamp:[NSString stringWithFormat:@"%f", [date timeIntervalSince1970]]];
			}];
    	});
	}];
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
        [self registerObserver];
		NSLog(@"[Direct.FM] Found token in keychain!");

		CFRelease(result);

		return true;
	}
	return false;
}

@end