#include <Foundation/Foundation.h>
#include <MacTypes.h>
#import <Security/Security.h>
#include <objc/objc.h>
#include <UIKit/UIWindow.h>
#import <CommonCrypto/CommonDigest.h>
#import "Scrobbler.h"
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
	scrobbler.selectedApps = apps;
	[scrobbler loadToken];

	NSLog(@"[Scrubble] Initialized Scrobbler!");
}

void updatePrefs() {
	NSUserDefaults *const prefs = [[NSUserDefaults alloc] initWithSuiteName:PREFS_BUNDLE_ID];

	enabled = (prefs && [prefs objectForKey:@"enabled"] ? [[prefs valueForKey:@"enabled"] boolValue] : YES );

	NSString *apiKey = [prefs objectForKey:@"apiKey"];
	NSString *apiSecret = [prefs objectForKey:@"apiSecret"];
	NSString *username = [prefs objectForKey:@"username"];
	NSString *password = [prefs objectForKey:@"password"];
	float scrobbleAfter = [prefs objectForKey:@"scrobbleAfter"] ? [[prefs objectForKey:@"scrobbleAfter"] floatValue] : 0.7;
	
	// Get enabled apps array from new format, with fallback to old individual toggles
	NSArray *selectedApps = [prefs arrayForKey:@"selectedApps"];
	NSMutableArray *apps = [[NSMutableArray alloc] init];
	
	if (selectedApps && selectedApps.count > 0) {
		// use new format
		[apps addObjectsFromArray:selectedApps];
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
	}
	
	NSLog(@"[Scrubble] Enabled apps: %@", apps);
	
	if (!apiKey || !apiSecret || !username || !password || !enabled) enabled = NO;
	else initScrobbler(apiKey, apiSecret, username, password, scrobbleAfter, apps);
}



int main(int argc, char *argv[], char *envp[]) {
	@autoreleasepool {
		NSLog(@"[Scrubble] Scrubble started!");

		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)updatePrefs, CFSTR("fr.rootfs.scrubbleprefs-updated"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		updatePrefs();
		CFRunLoopRun();
		return 0;
	}
}

