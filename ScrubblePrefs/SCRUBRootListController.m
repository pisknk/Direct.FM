#include "Preferences/PSSpecifier.h"
#include "Preferences/PSTableCell.h"
#import <Foundation/Foundation.h>
#include <objc/objc.h>
#include <UIKit/UIKit.h>
#include <stdbool.h>
#import "SCRUBRootListController.h"
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

@implementation SCRUBRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
        self.daemonRunning = false;
        [self loadSelectedApps];
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
}

- (void)loadSelectedApps {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"fr.rootfs.scrubbleprefs"];
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
    NSLog(@"Checking Scrubble status");
    @try{
        NSPipe *pipe = [NSPipe pipe];
        NSFileHandle *file = pipe.fileHandleForReading;

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = JBROOT_PATH_NSSTRING(@"/bin/sh");
        task.arguments = @[@"-c", [NSString stringWithFormat:@"%@ list | %@ scrubble | %@ '{print $1}'", JBROOT_PATH_NSSTRING(@"/usr/bin/launchctl"), JBROOT_PATH_NSSTRING(@"/usr/bin/grep"), JBROOT_PATH_NSSTRING(@"/usr/bin/awk")]];
        task.standardOutput = pipe;
        task.standardError = pipe;

        [task launch];
        [task waitUntilExit];

        NSData *data = [file readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [file closeFile];
        
        NSLog(@"Scrubble %@", output);

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
    NSString *command = [NSString stringWithFormat:@"sudo %@ %@ %@", JBROOT_PATH_NSSTRING(@"/usr/bin/launchctl"), action, @"fr.rootfs.scrubble"];

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Scrubble" message:[NSString stringWithFormat:@"In order to %@ Scrubble, you need to paste this command into NewTerm. \n The default password is alpine.", action] preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* openNewTermAction = [UIAlertAction actionWithTitle:@"Open NewTerm" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        UIPasteboard.generalPasteboard.string = command;
        [[objc_getClass("LSApplicationWorkspace") performSelector:@selector(defaultWorkspace)] performSelector:@selector(openApplicationWithBundleID:) withObject:@"ws.hbang.Terminal"];
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];

    [alertController addAction:openNewTermAction];
    [alertController addAction:cancelAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (NSString*)toggleDaemonLabel {
    return (self.daemonRunning ? @"Stop Scrubble" : @"Start Scrubble");
}

-(void) testLogin {
    NSString *username = [self readPreferenceValue:[self specifierForID:@"username"]];
    NSString *password = [self readPreferenceValue:[self specifierForID:@"password"]];
	NSString *apiKey = [self readPreferenceValue:[self specifierForID:@"apiKey"]];
    NSString *apiSecret = [self readPreferenceValue:[self specifierForID:@"apiSecret"]];

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
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:(success ? @"Login succeeded" : @"Login failed") message:(success ? nil : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]) preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *action = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:nil];

            [controller addAction:action];
            [self presentViewController:controller animated:YES completion:nil];
        });

	}] resume];
}

- (void)checkScrobbleStatus {
    // show loading indicator
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"Checking Scrobble Status" 
                                                                          message:@"Please wait..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    NSMutableString *statusMessage = [[NSMutableString alloc] init];
    NSMutableString *statusTitle = [[NSMutableString alloc] init];
    
    // check daemon status
    NSString *daemonStatus = [self daemonStatus:nil];
    BOOL daemonRunning = [daemonStatus isEqualToString:@"Running"];
    [statusMessage appendFormat:@"Daemon Status: %@\n", daemonStatus];
    
    // get debug info
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"fr.rootfs.scrubbleprefs"];
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
    NSString *apiKey = [self readPreferenceValue:[self specifierForID:@"apiKey"]];
    NSString *apiSecret = [self readPreferenceValue:[self specifierForID:@"apiSecret"]];
    
    if (!username || !password || !apiKey || !apiSecret) {
        [statusTitle setString:@"⚠️ Configuration Incomplete"];
        [statusMessage appendString:@"Last.fm Status: Missing credentials"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingAlert dismissViewControllerAnimated:NO completion:^{
                [self showStatusAlert:statusTitle.copy message:statusMessage.copy];
            }];
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
            [loadingAlert dismissViewControllerAnimated:NO completion:^{
                [self showStatusAlert:statusTitle.copy message:statusMessage.copy];
            }];
        });
    }] resume];
}

- (void)showStatusAlert:(NSString *)title message:(NSString *)message {
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
}

// debugging methods
- (NSString*)getScrobbleCount:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"fr.rootfs.scrubbleprefs"];
    NSInteger count = [defaults integerForKey:@"scrobbleCount"];
    return [NSString stringWithFormat:@"%ld", (long)count];
}

- (NSString*)getLastScrobbledTrack:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"fr.rootfs.scrubbleprefs"];
    NSString *lastTrack = [defaults stringForKey:@"lastScrobbledTrack"];
    return lastTrack ?: @"None";
}

- (NSString*)getCurrentPlayingApp:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"fr.rootfs.scrubbleprefs"];
    NSString *currentApp = [defaults stringForKey:@"currentPlayingApp"];
    return currentApp ?: @"None detected";
}

- (void)resetScrobbleCount {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"fr.rootfs.scrubbleprefs"];
    [defaults setInteger:0 forKey:@"scrobbleCount"];
    [defaults removeObjectForKey:@"lastScrobbledTrack"];
    [defaults removeObjectForKey:@"currentPlayingApp"];
    [defaults synchronize];
    
    // refresh the debug section
    [self reloadSpecifier:[self specifierForID:@"scrobbleCount"]];
    [self reloadSpecifier:[self specifierForID:@"lastScrobbledTrack"]];
    [self reloadSpecifier:[self specifierForID:@"currentPlayingApp"]];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Debug Info Reset" 
                                                                   message:@"Scrobble counter and debug info have been reset." 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

// app picker methods
- (void)showAppPicker {
    SCRUBAppPickerListController *appPicker = [[SCRUBAppPickerListController alloc] init];
    appPicker.availableApps = [self getInstalledMusicApps];
    appPicker.selectedAppBundleIDs = [self.selectedAppBundleIDs mutableCopy];
    appPicker.parentController = self;
    
    [self.navigationController pushViewController:appPicker animated:YES];
}

- (void)showSelectedAppsPopup {
    if (!self.selectedAppBundleIDs || self.selectedAppBundleIDs.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Apps Selected" 
                                                                       message:@"You haven't selected any apps to scrobble from yet. Tap 'Choose Apps to Scrobble' to select apps." 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSMutableArray *appNames = [[NSMutableArray alloc] init];
    for (NSString *bundleID in self.selectedAppBundleIDs) {
        [appNames addObject:[self getAppNameFromBundleID:bundleID]];
    }
    
    NSString *appList = [appNames componentsJoinedByString:@"\n• "];
    NSString *message = [NSString stringWithFormat:@"Currently scrobbling from these apps:\n\n• %@", appList];
    
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
}

- (void)saveSelectedApps {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"fr.rootfs.scrubbleprefs"];
    [defaults setObject:self.selectedAppBundleIDs forKey:@"selectedApps"];
    [defaults synchronize];
    
    // notify daemon of changes
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("fr.rootfs.scrubbleprefs-updated"), NULL, NULL, YES);
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
                    NSLog(@"[Scrubble] App detection failed for %@: %@", bundleID, exception.reason);
                }
            }
        }
    }
    
    // if detection failed or no apps were found, include all known apps
    if (musicApps.count == 0) {
        NSLog(@"[Scrubble] App detection failed, showing all known apps");
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

@end

// implementation of app picker controller
@implementation SCRUBAppPickerListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Select Apps";
    
    // add done button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                                           target:self 
                                                                                           action:@selector(donePressed)];
}

- (void)donePressed {
    [self saveSelectedApps];
    [self.navigationController popViewControllerAnimated:YES];
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
        [headerSpec setProperty:@"Select which music apps you want to scrobble from:" forKey:@"footerText"];
        [specs addObject:headerSpec];
        
        // get available apps
        self.availableApps = [self getInstalledMusicApps];
        
        // create toggle for each app
        for (NSDictionary *appInfo in self.availableApps) {
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
            [appSpec setProperty:@YES forKey:@"default"];
            [specs addObject:appSpec];
        }
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)getAppEnabled:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    return @([self.selectedAppBundleIDs containsObject:bundleID]);
}

- (void)setAppEnabled:(id)value forSpecifier:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    BOOL enabled = [value boolValue];
    
    if (enabled) {
        if (![self.selectedAppBundleIDs containsObject:bundleID]) {
            [self.selectedAppBundleIDs addObject:bundleID];
        }
    } else {
        [self.selectedAppBundleIDs removeObject:bundleID];
    }
}

- (void)saveSelectedApps {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"fr.rootfs.scrubbleprefs"];
    [defaults setObject:self.selectedAppBundleIDs forKey:@"selectedApps"];
    [defaults synchronize];
    
    // notify daemon of changes
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("fr.rootfs.scrubbleprefs-updated"), NULL, NULL, YES);
    
    // refresh parent controller
    if (self.parentController) {
        [self.parentController reloadSpecifier:[self.parentController specifierForID:@"selectedAppsDisplay"]];
    }
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
                    NSLog(@"[Scrubble] App detection failed for %@: %@", bundleID, exception.reason);
                }
            }
        }
    }
    
    // if detection failed or no apps were found, include all known apps
    if (musicApps.count == 0) {
        NSLog(@"[Scrubble] App detection failed, showing all known apps");
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

@end
