#include <Foundation/Foundation.h>
#include <MacTypes.h>
#import <Security/Security.h>
#include <objc/objc.h>
#include <UIKit/UIWindow.h>
#import <CommonCrypto/CommonDigest.h>
#import "Scrobbler.h"
#import "Constants.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL enabled;

static Scrobbler *scrobbler;

void initScrobbler(NSString *apiKey, NSString *apiSecret, NSString *username, NSString *password, float scrobbleAfter, NSArray *apps) {
	if (!scrobbler) scrobbler = [[Scrobbler alloc] init];
	scrobbler.apiKey = apiKey;
	scrobbler.apiSecret = apiSecret;
	scrobbler.username = username;
	scrobbler.password = password;
	scrobbler.loggedIn = false;
	scrobbler.scrobbleAfter = scrobbleAfter;
	// ensure selectedApps is set as a copy to avoid issues
	scrobbler.selectedApps = apps ? [apps copy] : @[];
	[scrobbler loadToken];

	NSLog(@"[Direct.FM] Initialized Scrobbler with %lu selected apps: %@", (unsigned long)[scrobbler.selectedApps count], scrobbler.selectedApps);
}

void updatePrefs() {
	NSUserDefaults *const prefs = [[NSUserDefaults alloc] initWithSuiteName:PREFS_BUNDLE_ID];

	enabled = (prefs && [prefs objectForKey:@"enabled"] ? [[prefs valueForKey:@"enabled"] boolValue] : YES );

	NSString *apiKey = @LASTFM_API_KEY;
	NSString *apiSecret = @LASTFM_API_SECRET;
	NSString *username = [prefs objectForKey:@"username"];
	NSString *password = [prefs objectForKey:@"password"];
	float scrobbleAfter = [prefs objectForKey:@"scrobbleAfter"] ? [[prefs objectForKey:@"scrobbleAfter"] floatValue] : 0.7;
	
	// Get enabled apps array from new format, with fallback to old individual toggles
	NSArray *selectedApps = [prefs arrayForKey:@"selectedApps"];
	NSMutableArray *apps = [[NSMutableArray alloc] init];
	
	if (selectedApps && selectedApps.count > 0) {
		// use new format - ensure all items are strings
		for (id app in selectedApps) {
			if ([app isKindOfClass:[NSString class]]) {
				[apps addObject:app];
			} else {
				NSLog(@"[Direct.FM] Warning: Invalid app entry in selectedApps: %@", app);
			}
		}
		NSLog(@"[Direct.FM] Loaded %lu apps from preferences", (unsigned long)[apps count]);
	} else {
		// fallback to old individual toggle switches for migration
		BOOL enableAppleMusic = [prefs objectForKey:@"enableAppleMusic"] ? [[prefs objectForKey:@"enableAppleMusic"] boolValue] : YES;
		BOOL enableSpotify = [prefs objectForKey:@"enableSpotify"] ? [[prefs objectForKey:@"enableSpotify"] boolValue] : YES;
		BOOL enableYouTubeMusic = [prefs objectForKey:@"enableYouTubeMusic"] ? [[prefs objectForKey:@"enableYouTubeMusic"] boolValue] : YES;
		
		if (enableAppleMusic) [apps addObject:@"com.apple.Music"];
		if (enableSpotify) [apps addObject:@"com.spotify.client"];
		if (enableYouTubeMusic) [apps addObject:@"com.google.ios.youtubemusic"];
		
		// save migrated settings
		[prefs setObject:[apps copy] forKey:@"selectedApps"];
		[prefs synchronize];
		NSLog(@"[Direct.FM] Migrated %lu apps from old format", (unsigned long)[apps count]);
	}
	
	NSLog(@"[Direct.FM] Enabled apps (%lu): %@", (unsigned long)[apps count], apps);
	
	if (!username || !password || !enabled) enabled = NO;
	else initScrobbler(apiKey, apiSecret, username, password, scrobbleAfter, apps);
}



int main(int argc, char *argv[], char *envp[]) {
	@autoreleasepool {
		NSLog(@"[Direct.FM] Direct.FM started!");

		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)updatePrefs, CFSTR("playpass.direct.fmprefs-updated"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		updatePrefs();
		CFRunLoopRun();
		return 0;
	}
}

