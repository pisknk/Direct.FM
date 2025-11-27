#include "Preferences/PSSpecifier.h"
#include "Preferences/PSTableCell.h"
#import <Foundation/Foundation.h>
#include <objc/objc.h>
#include <UIKit/UIKit.h>
#include <stdbool.h>
#import "DirectFMRootListController.h"
#import "Constants.h"
#import <spawn.h>
#import <libroot.h>
#import "include/NSTask.h"
#import <objc/runtime.h>
#import <CommonCrypto/CommonCrypto.h>
#import <Foundation/NSURLSession.h>

// forward declaration for LSApplicationWorkspace - using objc_getClass to avoid linking issues
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)bundleIdentifier;
@end

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

@implementation DirectFMRootListController

// helper method for ios 8 compatibility
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message buttonTitle:(NSString *)buttonTitle {
    [self showAlertWithTitle:title message:message buttonTitle:buttonTitle completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message buttonTitle:(NSString *)buttonTitle completion:(void (^)(void))completion {
    if ([UIAlertController class]) {
        // ios 9+ code
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *action = [UIAlertAction actionWithTitle:buttonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            if (completion) completion();
        }];
        [alert addAction:action];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        // ios 8 fallback
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:buttonTitle otherButtonTitles:nil];
        [alertView show];
        if (completion) completion();
    }
}

- (NSArray *)specifiers {
	if (!_specifiers) {
        self.daemonRunning = false;
        [self loadSelectedApps];
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
}

- (void)loadSelectedApps {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSArray *savedApps = [defaults arrayForKey:@"selectedApps"];
    
    if (savedApps) {
        self.selectedAppBundleIDs = [savedApps mutableCopy];
    } else {
        // migrate from old individual toggles
        self.selectedAppBundleIDs = [[NSMutableArray alloc] init];
        BOOL enableAppleMusic = [defaults objectForKey:@"enableAppleMusic"] ? [[defaults objectForKey:@"enableAppleMusic"] boolValue] : YES;
        BOOL enableSpotify = [defaults objectForKey:@"enableSpotify"] ? [[defaults objectForKey:@"enableSpotify"] boolValue] : YES;
        BOOL enableYouTubeMusic = [defaults objectForKey:@"enableYouTubeMusic"] ? [[defaults objectForKey:@"enableYouTubeMusic"] boolValue] : YES;
        
        if (enableAppleMusic) [self.selectedAppBundleIDs addObject:@"com.apple.Music"];
        if (enableSpotify) [self.selectedAppBundleIDs addObject:@"com.spotify.client"];
        if (enableYouTubeMusic) [self.selectedAppBundleIDs addObject:@"com.google.ios.youtubemusic"];
        
        // save migrated settings
        [defaults setObject:self.selectedAppBundleIDs forKey:@"selectedApps"];
        [defaults synchronize];
    }
}

- (void)open:(PSSpecifier *)btn {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[btn propertyForKey:@"url"]] options:@{} completionHandler:nil];
}

- (NSString*)daemonStatus:(PSSpecifier*)sender {
    NSLog(@"Checking Direct.FM status");
    @try{
        NSPipe *pipe = [NSPipe pipe];
        NSFileHandle *file = pipe.fileHandleForReading;

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = JBROOT_PATH_NSSTRING(@"/bin/sh");
        task.arguments = @[@"-c", [NSString stringWithFormat:@"%@ list | %@ playpass.direct.fm | %@ '{print $1}'", JBROOT_PATH_NSSTRING(@"/usr/bin/launchctl"), JBROOT_PATH_NSSTRING(@"/usr/bin/grep"), JBROOT_PATH_NSSTRING(@"/usr/bin/awk")]];
        task.standardOutput = pipe;
        task.standardError = pipe;

        [task launch];
        [task waitUntilExit];

        NSData *data = [file readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [file closeFile];
        
        NSLog(@"Direct.FM %@", output);

        if (!output || [[output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""]) return @"Stopped";
        
        self.daemonRunning = ![output hasPrefix:@"-"];
        [self reloadDaemonToggleLabel];
        return (self.daemonRunning ? @"Running" : @"Stopped");
    }
    @catch(NSException *e){
        NSLog(@"Exception: %@", e.reason);
    }

    return @"Stopped";
}

-(void) reloadDaemonToggleLabel {
    PSSpecifier *daemonToggleLabel = [self specifierForID:@"daemonToggle"];
    if (daemonToggleLabel) daemonToggleLabel.name = [self toggleDaemonLabel];
}

-(void) reloadDaemonStatus {
    PSSpecifier *daemonStatus = [self specifierForID:@"daemonStatus"];
    if (daemonStatus) [self reloadSpecifier:daemonStatus];
    [self reloadDaemonToggleLabel];
}

- (void)toggleDaemon {
    NSString *action = (!self.daemonRunning ? @"start" : @"stop");
    NSString *command = [NSString stringWithFormat:@"sudo %@ %@ %@", JBROOT_PATH_NSSTRING(@"/usr/bin/launchctl"), action, @"playpass.direct.fm"];

    // use ios 8 compatible uialertview instead of uialertcontroller for ios 8.4.1 compatibility
    if ([UIAlertController class]) {
        // ios 9+ code
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Direct.FM" message:[NSString stringWithFormat:@"In order to %@ Direct.FM, you need to paste this command into NewTerm. \n The default password is alpine.", action] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* openNewTermAction = [UIAlertAction actionWithTitle:@"Open NewTerm" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            UIPasteboard.generalPasteboard.string = command;
            [[objc_getClass("LSApplicationWorkspace") performSelector:@selector(defaultWorkspace)] performSelector:@selector(openApplicationWithBundleID:) withObject:@"ws.hbang.Terminal"];
        }];

        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];

        [alertController addAction:openNewTermAction];
        [alertController addAction:cancelAction];

        [self presentViewController:alertController animated:YES completion:nil];
    } else {
        // ios 8 fallback using uialertview
        UIPasteboard.generalPasteboard.string = command;
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Direct.FM" 
                                                            message:[NSString stringWithFormat:@"Command copied to clipboard: %@\n\nPaste this into NewTerm. The default password is alpine.", command] 
                                                           delegate:nil 
                                                  cancelButtonTitle:@"OK" 
                                                  otherButtonTitles:nil];
        [alertView show];
    }
}

- (NSString*)toggleDaemonLabel {
    return (self.daemonRunning ? @"Stop Direct.FM" : @"Start Direct.FM");
}

-(void) login {
    NSString *username = [self readPreferenceValue:[self specifierForID:@"username"]];
    NSString *password = [self readPreferenceValue:[self specifierForID:@"password"]];
	// use hardcoded api credentials (macro already includes @"" so don't add @)
	NSString *apiKey = LASTFM_API_KEY;
    NSString *apiSecret = LASTFM_API_SECRET;

    NSString *sigContent = [NSString stringWithFormat:@"api_key%@method%@password%@username%@%@", apiKey, @"auth.getMobileSession", password, username, apiSecret];
	NSString *sig = md5(sigContent);
	
	NSString *query = queryString(@{@"method": @"auth.getMobileSession", @"username": username, @"password": password, @"api_key": apiKey, @"api_sig": sig, @"format": @"json"});

	NSURL *url = [NSURL URLWithString:@"https://ws.audioscrobbler.com/2.0/"];

	NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:url];
	[req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [req setHTTPBody:[query dataUsingEncoding:NSUTF8StringEncoding]];

	[[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
		BOOL success = [resp statusCode] == 200;

        dispatch_async(dispatch_get_main_queue(), ^{
            // ios 8 compatible alert handling
            if ([UIAlertController class]) {
                // ios 9+ code
                UIAlertController *controller = [UIAlertController alertControllerWithTitle:(success ? @"Login succeeded" : @"Login failed") message:(success ? nil : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]) preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *action = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:nil];

                [controller addAction:action];
                [self presentViewController:controller animated:YES completion:nil];
            } else {
                // ios 8 fallback
                NSString *message = success ? @"Login succeeded" : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                [self showAlertWithTitle:(success ? @"Login succeeded" : @"Login failed") message:message buttonTitle:@"Ok"];
            }
        });

	}] resume];
}

- (void)checkScrobbleStatus {
    // show loading indicator - ios 8 compatible
    UIViewController *loadingAlert = nil;
    if ([UIAlertController class]) {
        // ios 9+ code
        loadingAlert = [UIAlertController alertControllerWithTitle:@"Checking Scrobble Status" 
                                                            message:@"Please wait..." 
                                                     preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:loadingAlert animated:YES completion:nil];
    } else {
        // ios 8 fallback - show alert at the end since we can't show loading
        // we'll just show the final result
    }
    
    NSMutableString *statusMessage = [[NSMutableString alloc] init];
    NSMutableString *statusTitle = [[NSMutableString alloc] init];
    
    // check daemon status
    NSString *daemonStatus = [self daemonStatus:nil];
    BOOL daemonRunning = [daemonStatus isEqualToString:@"Running"];
    [statusMessage appendFormat:@"Daemon Status: %@\n", daemonStatus];
    
    // get debug info
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSInteger scrobbleCount = [defaults integerForKey:@"scrobbleCount"];
    NSString *lastTrack = [defaults stringForKey:@"lastScrobbledTrack"] ?: @"None";
    NSString *currentApp = [defaults stringForKey:@"currentPlayingApp"] ?: @"None detected";
    
    [statusMessage appendFormat:@"Scrobbles: %ld\n", (long)scrobbleCount];
    [statusMessage appendFormat:@"Last Track: %@\n", lastTrack];
    [statusMessage appendFormat:@"Current App: %@\n\n", currentApp];
    
    // get selected apps
    NSArray *selectedApps = [defaults arrayForKey:@"selectedApps"];
    if (selectedApps && selectedApps.count > 0) {
        NSMutableArray *appNames = [[NSMutableArray alloc] init];
        for (NSString *bundleID in selectedApps) {
            [appNames addObject:[self getAppNameFromBundleID:bundleID]];
        }
        [statusMessage appendFormat:@"Enabled Apps: %@\n\n", [appNames componentsJoinedByString:@", "]];
    } else {
        [statusMessage appendString:@"Enabled Apps: None selected\n\n"];
    }
    
    // test last.fm connectivity
    NSString *username = [self readPreferenceValue:[self specifierForID:@"username"]];
    NSString *password = [self readPreferenceValue:[self specifierForID:@"password"]];
    // use hardcoded api credentials (macro already includes @"" so don't add @)
    NSString *apiKey = LASTFM_API_KEY;
    NSString *apiSecret = LASTFM_API_SECRET;
    
    if (!username || !password) {
        [statusTitle setString:@"⚠️ Configuration Incomplete"];
        [statusMessage appendString:@"Last.fm Status: Missing username or password"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (loadingAlert) {
                [loadingAlert dismissViewControllerAnimated:NO completion:^{
                    [self showStatusAlert:statusTitle.copy message:statusMessage.copy];
                }];
            } else {
                // ios 8 fallback - just show the result
                [self showStatusAlert:statusTitle.copy message:statusMessage.copy];
            }
        });
        return;
    }
    
    // test last.fm authentication
    NSString *sigContent = [NSString stringWithFormat:@"api_key%@method%@password%@username%@%@", apiKey, @"auth.getMobileSession", password, username, apiSecret];
    NSString *sig = md5(sigContent);
    NSString *query = queryString(@{@"method": @"auth.getMobileSession", @"username": username, @"password": password, @"api_key": apiKey, @"api_sig": sig, @"format": @"json"});
    
    NSURL *url = [NSURL URLWithString:@"https://ws.audioscrobbler.com/2.0/"];
    NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [req setHTTPBody:[query dataUsingEncoding:NSUTF8StringEncoding]];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
        BOOL authSuccess = [resp statusCode] == 200;
        
        if (error) {
            [statusMessage appendFormat:@"Last.fm Status: Network error - %@", error.localizedDescription];
            [statusTitle setString:@"❌ Connection Failed"];
        } else if (authSuccess) {
            [statusMessage appendString:@"Last.fm Status: ✅ Connected and authenticated"];
            if (daemonRunning) {
                [statusTitle setString:@"✅ All Systems Operational"];
            } else {
                [statusTitle setString:@"⚠️ Daemon Not Running"];
            }
        } else {
            [statusMessage appendString:@"Last.fm Status: ❌ Authentication failed"];
            [statusTitle setString:@"❌ Authentication Error"];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (loadingAlert) {
                [loadingAlert dismissViewControllerAnimated:NO completion:^{
                    [self showStatusAlert:statusTitle.copy message:statusMessage.copy];
                }];
            } else {
                // ios 8 fallback - just show the result
                [self showStatusAlert:statusTitle.copy message:statusMessage.copy];
            }
        });
    }] resume];
}

- (void)showStatusAlert:(NSString *)title message:(NSString *)message {
    if ([UIAlertController class]) {
        // ios 9+ code
        UIAlertController *statusAlert = [UIAlertController alertControllerWithTitle:title 
                                                                             message:message 
                                                                      preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [statusAlert addAction:okAction];
        
        // add action to refresh daemon status if needed
        if ([title containsString:@"Daemon Not Running"]) {
            UIAlertAction *refreshAction = [UIAlertAction actionWithTitle:@"Refresh Status" 
                                                                    style:UIAlertActionStyleDefault 
                                                                  handler:^(UIAlertAction * _Nonnull action) {
                [self reloadDaemonStatus];
            }];
            [statusAlert addAction:refreshAction];
        }
        
        [self presentViewController:statusAlert animated:YES completion:nil];
    } else {
        // ios 8 fallback
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title 
                                                            message:message 
                                                           delegate:nil 
                                                  cancelButtonTitle:@"OK" 
                                                  otherButtonTitles:nil];
        [alertView show];
        
        // note: refresh functionality not available in ios 8 fallback
        // user will need to manually refresh
    }
}

// debugging methods
- (NSString*)getScrobbleCount:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSInteger count = [defaults integerForKey:@"scrobbleCount"];
    return [NSString stringWithFormat:@"%ld", (long)count];
}

- (NSString*)getLastScrobbledTrack:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSString *lastTrack = [defaults stringForKey:@"lastScrobbledTrack"];
    return lastTrack ?: @"None";
}

- (NSString*)getCurrentPlayingApp:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSString *currentApp = [defaults stringForKey:@"currentPlayingApp"];
    return currentApp ?: @"None detected";
}

- (NSString*)getCachedScrobblesCount:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSInteger count = [defaults integerForKey:@"cachedScrobblesCount"];
    return [NSString stringWithFormat:@"%ld", (long)count];
}

- (NSString*)getLastCacheRetryStatus:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSString *status = [defaults stringForKey:@"lastCacheRetryStatus"];
    return status ?: @"Never retried";
}

- (void)retryCachedScrobbles {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSInteger cachedCount = [defaults integerForKey:@"cachedScrobblesCount"];
    
    if (cachedCount == 0) {
        [self showAlertWithTitle:@"No Cached Scrobbles" message:@"There are no cached scrobbles to retry." buttonTitle:@"OK"];
        return;
    }
    
    // show confirmation alert
    NSString *message = [NSString stringWithFormat:@"Retry %ld cached scrobble%@? This will attempt to submit them to last.fm.", (long)cachedCount, cachedCount == 1 ? @"" : @"s"];
    
    if ([UIAlertController class]) {
        // ios 9+ code
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Retry Cached Scrobbles" 
                                                                       message:message 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *retryAction = [UIAlertAction actionWithTitle:@"Retry" 
                                                             style:UIAlertActionStyleDefault 
                                                           handler:^(UIAlertAction * _Nonnull action) {
            // send notification to daemon to retry
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("playpass.direct.fm-retry-cache"), NULL, NULL, YES);
            
            // show loading message
            [self showAlertWithTitle:@"Retrying..." message:@"Submitting cached scrobbles. This may take a moment." buttonTitle:@"OK"];
            
            // refresh cache count after a delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self reloadSpecifier:[self specifierForID:@"cachedScrobblesCount"]];
                [self reloadSpecifier:[self specifierForID:@"lastCacheRetryStatus"]];
            });
        }];
        
        [alert addAction:cancelAction];
        [alert addAction:retryAction];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        // ios 8 fallback
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Retry Cached Scrobbles" 
                                                            message:message 
                                                           delegate:self 
                                                  cancelButtonTitle:@"Cancel" 
                                                  otherButtonTitles:@"Retry", nil];
        alertView.tag = 100; // tag to identify this alert
        [alertView show];
    }
}

- (void)resetScrobbleCount {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    [defaults setInteger:0 forKey:@"scrobbleCount"];
    [defaults removeObjectForKey:@"lastScrobbledTrack"];
    [defaults removeObjectForKey:@"currentPlayingApp"];
    [defaults synchronize];
    
    // refresh the debug section
    [self reloadSpecifier:[self specifierForID:@"scrobbleCount"]];
    [self reloadSpecifier:[self specifierForID:@"lastScrobbledTrack"]];
    [self reloadSpecifier:[self specifierForID:@"currentPlayingApp"]];
    
    [self showAlertWithTitle:@"Debug Info Reset" message:@"Scrobble counter and debug info have been reset." buttonTitle:@"OK"];
}

// app picker methods
- (void)showAppPicker {
    DirectFMAppPickerController *appPicker = [[DirectFMAppPickerController alloc] init];
    appPicker.directFMRootController = self;
    
    [self.navigationController pushViewController:appPicker animated:YES];
}

- (void)showSelectedAppsPopup {
    if (!self.selectedAppBundleIDs || self.selectedAppBundleIDs.count == 0) {
        [self showAlertWithTitle:@"No Apps Selected" message:@"You haven't selected any apps to scrobble from yet. Tap 'Choose Apps to Scrobble' to select apps." buttonTitle:@"OK"];
        return;
    }
    
    NSMutableArray *appNames = [[NSMutableArray alloc] init];
    for (NSString *bundleID in self.selectedAppBundleIDs) {
        [appNames addObject:[self getAppNameFromBundleID:bundleID]];
    }
    
    NSString *appList = [appNames componentsJoinedByString:@"\n• "];
    NSString *message = [NSString stringWithFormat:@"Currently scrobbling from these apps:\n\n• %@", appList];
    
    if ([UIAlertController class]) {
        // ios 9+ code
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Selected Apps" 
                                                                       message:message 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        UIAlertAction *editAction = [UIAlertAction actionWithTitle:@"Edit Selection" 
                                                             style:UIAlertActionStyleDefault 
                                                           handler:^(UIAlertAction * _Nonnull action) {
            [self showAppPicker];
        }];
        
        [alert addAction:okAction];
        [alert addAction:editAction];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        // ios 8 fallback - show alert with just ok, then ask if they want to edit
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Selected Apps" 
                                                            message:[message stringByAppendingString:@"\n\nTap 'Choose Apps to Scrobble' to edit selection."] 
                                                           delegate:nil 
                                                  cancelButtonTitle:@"OK" 
                                                  otherButtonTitles:nil];
        [alertView show];
    }
}

- (void)saveSelectedApps {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    [defaults setObject:self.selectedAppBundleIDs forKey:@"selectedApps"];
    [defaults synchronize];
    
    // notify daemon of changes
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("playpass.direct.fmprefs-updated"), NULL, NULL, YES);
}

- (NSArray *)getInstalledMusicApps {
    NSMutableArray *musicApps = [[NSMutableArray alloc] init];
    
    // known music apps with their bundle ids and display names
    NSDictionary *knownApps = @{
        @"com.apple.Music": @"Apple Music",
        @"com.spotify.client": @"Spotify",
        @"com.google.ios.youtubemusic": @"YouTube Music",
        @"com.pandora": @"Pandora",
        @"com.amazon.mp3": @"Amazon Music",
        @"com.soundcloud.TouchApp": @"SoundCloud",
        @"com.aspiro.tidal": @"TIDAL",
        @"com.deezer.Deezer": @"Deezer",
        @"com.apple.podcasts": @"Apple Podcasts",
        @"com.overcast.overcast-ios": @"Overcast",
        @"fm.last.scrobbler": @"Last.fm",
        @"com.bandcamp.client": @"Bandcamp"
    };
    
    // try to check which apps are actually installed using runtime loading to avoid linking issues
    Class LSApplicationWorkspaceClass = objc_getClass("LSApplicationWorkspace");
    if (LSApplicationWorkspaceClass) {
        id workspace = [LSApplicationWorkspaceClass performSelector:@selector(defaultWorkspace)];
        if (workspace) {
            for (NSString *bundleID in knownApps.allKeys) {
                @try {
                    BOOL isInstalled = NO;
                    if ([workspace respondsToSelector:@selector(applicationIsInstalled:)]) {
                        isInstalled = [[workspace performSelector:@selector(applicationIsInstalled:) withObject:bundleID] boolValue];
                    }
                    if (isInstalled) {
                        [musicApps addObject:@{@"bundleID": bundleID, @"name": knownApps[bundleID]}];
                    }
                } @catch (NSException *exception) {
                    // if detection fails, we'll fall back to showing all apps
                    NSLog(@"[Direct.FM] App detection failed for %@: %@", bundleID, exception.reason);
                }
            }
        }
    }
    
    // if detection failed or no apps were found, include all known apps
    if (musicApps.count == 0) {
        NSLog(@"[Direct.FM] App detection failed, showing all known apps");
        for (NSString *bundleID in knownApps.allKeys) {
            [musicApps addObject:@{@"bundleID": bundleID, @"name": knownApps[bundleID]}];
        }
    }
    
    // always ensure the default three are included
    NSArray *defaultApps = @[@"com.apple.Music", @"com.spotify.client", @"com.google.ios.youtubemusic"];
    for (NSString *bundleID in defaultApps) {
        BOOL alreadyAdded = NO;
        for (NSDictionary *app in musicApps) {
            if ([app[@"bundleID"] isEqualToString:bundleID]) {
                alreadyAdded = YES;
                break;
            }
        }
        if (!alreadyAdded) {
            [musicApps addObject:@{@"bundleID": bundleID, @"name": knownApps[bundleID]}];
        }
    }
    
    return [musicApps copy];
}

- (NSString *)getAppNameFromBundleID:(NSString *)bundleID {
    NSDictionary *knownApps = @{
        @"com.apple.Music": @"Apple Music",
        @"com.spotify.client": @"Spotify",
        @"com.google.ios.youtubemusic": @"YouTube Music",
        @"com.pandora": @"Pandora",
        @"com.amazon.mp3": @"Amazon Music",
        @"com.soundcloud.TouchApp": @"SoundCloud",
        @"com.aspiro.tidal": @"TIDAL",
        @"com.deezer.Deezer": @"Deezer",
        @"com.apple.podcasts": @"Apple Podcasts",
        @"com.overcast.overcast-ios": @"Overcast",
        @"fm.last.scrobbler": @"Last.fm",
        @"com.bandcamp.client": @"Bandcamp"
    };
    
    return knownApps[bundleID] ?: bundleID;
}

- (NSString *)getSelectedAppsDisplay:(PSSpecifier*)sender {
    if (!self.selectedAppBundleIDs || self.selectedAppBundleIDs.count == 0) {
        return @"None selected";
    }
    
    NSMutableArray *appNames = [[NSMutableArray alloc] init];
    for (NSString *bundleID in self.selectedAppBundleIDs) {
        [appNames addObject:[self getAppNameFromBundleID:bundleID]];
    }
    
    if (appNames.count <= 3) {
        return [appNames componentsJoinedByString:@", "];
    } else {
        return [NSString stringWithFormat:@"%@, and %lu more", [[appNames subarrayWithRange:NSMakeRange(0, 2)] componentsJoinedByString:@", "], (unsigned long)(appNames.count - 2)];
    }
}

// UIAlertViewDelegate for iOS 8 compatibility
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 100 && buttonIndex == 1) {
        // retry button pressed
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("playpass.direct.fm-retry-cache"), NULL, NULL, YES);
        
        // show loading message
        [self showAlertWithTitle:@"Retrying..." message:@"Submitting cached scrobbles. This may take a moment." buttonTitle:@"OK"];
        
        // refresh cache count after a delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self reloadSpecifier:[self specifierForID:@"cachedScrobblesCount"]];
            [self reloadSpecifier:[self specifierForID:@"lastCacheRetryStatus"]];
        });
    }
}

@end

// implementation of app picker - fallback implementation that works without AltList headers
@implementation DirectFMAppPickerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Select Apps";
    
    // load selected apps
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSArray *selectedApps = [defaults arrayForKey:@"selectedApps"];
    if (selectedApps) {
        self.selectedApplications = [NSMutableSet setWithArray:selectedApps];
    } else {
        self.selectedApplications = [[NSMutableSet alloc] init];
    }
    
    // add done button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                                           target:self 
                                                                                           action:@selector(donePressed)];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[NSMutableArray alloc] init];
        
        // header
        PSSpecifier *headerSpec = [PSSpecifier preferenceSpecifierNamed:@"" 
                                                                  target:nil 
                                                                     set:nil 
                                                                     get:nil 
                                                                  detail:nil 
                                                                    cell:PSGroupCell 
                                                                    edit:nil];
        [headerSpec setProperty:@"Select which apps you want to scrobble from. This includes all user-installed apps that could potentially play music." forKey:@"footerText"];
        [specs addObject:headerSpec];
        
        // get installed apps using LSApplicationWorkspace
        NSArray *installedApps = [self getInstalledUserApps];
        
        // create toggle for each app
        for (NSDictionary *appInfo in installedApps) {
            NSString *bundleID = appInfo[@"bundleID"];
            NSString *appName = appInfo[@"name"];
            
            PSSpecifier *appSpec = [PSSpecifier preferenceSpecifierNamed:appName 
                                                                  target:self 
                                                                     set:@selector(setAppEnabled:forSpecifier:) 
                                                                     get:@selector(getAppEnabled:) 
                                                                  detail:nil 
                                                                    cell:PSSwitchCell 
                                                                    edit:nil];
            [appSpec setProperty:bundleID forKey:@"bundleID"];
            [appSpec setProperty:bundleID forKey:@"subtitle"]; // show bundle ID as subtitle
            [appSpec setProperty:@YES forKey:@"default"];
            [specs addObject:appSpec];
        }
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)getAppEnabled:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    return @([self.selectedApplications containsObject:bundleID]);
}

- (void)setAppEnabled:(id)value forSpecifier:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    BOOL enabled = [value boolValue];
    
    if (enabled) {
        [self.selectedApplications addObject:bundleID];
    } else {
        [self.selectedApplications removeObject:bundleID];
    }
}

- (void)donePressed {
    // save selected apps
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    [defaults setObject:[self.selectedApplications allObjects] forKey:@"selectedApps"];
    [defaults synchronize];
    
    // notify daemon of changes
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("playpass.direct.fmprefs-updated"), NULL, NULL, YES);
    
    // refresh parent controller
    if (self.directFMRootController) {
        [self.directFMRootController reloadSpecifier:[self.directFMRootController specifierForID:@"selectedAppsDisplay"]];
        // also update the selectedAppBundleIDs array
        self.directFMRootController.selectedAppBundleIDs = [[self.selectedApplications allObjects] mutableCopy];
    }
    
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSArray *)getInstalledUserApps {
    NSMutableArray *userApps = [[NSMutableArray alloc] init];
    
    // use LSApplicationWorkspace to get all installed apps
    Class LSApplicationWorkspaceClass = objc_getClass("LSApplicationWorkspace");
    if (LSApplicationWorkspaceClass) {
        id workspace = [LSApplicationWorkspaceClass performSelector:@selector(defaultWorkspace)];
        if (workspace && [workspace respondsToSelector:@selector(allInstalledApplications)]) {
            NSArray *allApps = [workspace performSelector:@selector(allInstalledApplications)];
            
            for (id app in allApps) {
                @try {
                    // get app properties
                    NSString *bundleID = [app performSelector:@selector(bundleIdentifier)];
                    NSString *displayName = [app performSelector:@selector(localizedName)];
                    
                    // filter out system apps
                    BOOL isSystemApp = NO;
                    BOOL isInternalApp = NO;
                    
                    if ([app respondsToSelector:@selector(isSystemApplication)]) {
                        isSystemApp = [[app performSelector:@selector(isSystemApplication)] boolValue];
                    }
                    if ([app respondsToSelector:@selector(isInternalApplication)]) {
                        isInternalApp = [[app performSelector:@selector(isInternalApplication)] boolValue];
                    }
                    
                    // only include user apps
                    if (!isSystemApp && !isInternalApp && bundleID && displayName) {
                        [userApps addObject:@{
                            @"bundleID": bundleID,
                            @"name": displayName
                        }];
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[Direct.FM] Error processing app: %@", exception.reason);
                }
            }
        }
    }
    
    // sort apps alphabetically
    [userApps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    
    return [userApps copy];
}

// compatibility method
- (BOOL)shouldShowApplication:(LSApplicationProxy *)application {
    return YES; // not used in this implementation
}

@end
