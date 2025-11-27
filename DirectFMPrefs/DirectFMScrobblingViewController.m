#import "DirectFMScrobblingViewController.h"
#import "DirectFMCachedScrobblesViewController.h"
#import "DirectFMRootListController.h"
#import <Preferences/PSSpecifier.h>

@implementation DirectFMScrobblingViewController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[NSMutableArray alloc] init];
        
        // apps section
        PSSpecifier *appsGroup = [PSSpecifier groupSpecifierWithName:@"Apps"];
        [appsGroup setProperty:@"Select which apps to scrobble from" forKey:@"footerText"];
        [specs addObject:appsGroup];
        
        PSSpecifier *selectedApps = [PSSpecifier preferenceSpecifierNamed:@"Selected Apps"
                                                                   target:self
                                                                      set:nil
                                                                      get:@selector(getSelectedAppsDisplay:)
                                                                   detail:nil
                                                                     cell:PSTitleValueCell
                                                                     edit:nil];
        [selectedApps setProperty:@"selectedAppsDisplay" forKey:@"id"];
        [specs addObject:selectedApps];
        
        PSSpecifier *chooseApps = [PSSpecifier preferenceSpecifierNamed:@"Choose Apps to Scrobble"
                                                                 target:self
                                                                    set:nil
                                                                    get:nil
                                                                 detail:nil
                                                                   cell:PSButtonCell
                                                                   edit:nil];
        chooseApps.buttonAction = @selector(showAppPicker);
        [specs addObject:chooseApps];
        
        // delay section
        PSSpecifier *delayGroup = [PSSpecifier groupSpecifierWithName:@"Scrobble Delay"];
        [delayGroup setProperty:@"Percentage of track duration to wait before scrobbling" forKey:@"footerText"];
        [specs addObject:delayGroup];
        
        PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:nil
                                                             target:self
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSSliderCell
                                                               edit:nil];
        [slider setProperty:@"scrobbleAfter" forKey:@"key"];
        [slider setProperty:@"playpass.direct.fmprefs" forKey:@"defaults"];
        [slider setProperty:@0.7 forKey:@"default"];
        [slider setProperty:@0 forKey:@"min"];
        [slider setProperty:@1 forKey:@"max"];
        [slider setProperty:@YES forKey:@"showValue"];
        [slider setProperty:@"playpass.direct.fmprefs-updated" forKey:@"PostNotification"];
        [specs addObject:slider];
        
        // tag cleaning section
        PSSpecifier *tagsGroup = [PSSpecifier groupSpecifierWithName:@"Tag Cleaning"];
        [tagsGroup setProperty:@"Automatically remove common tags like \"• Video Available\", \"[Explicit]\", \"Single\", years, \"Remaster\", etc. from track names" forKey:@"footerText"];
        [specs addObject:tagsGroup];
        
        PSSpecifier *removeTags = [PSSpecifier preferenceSpecifierNamed:@"Remove Extra Tags"
                                                                 target:self
                                                                    set:@selector(setPreferenceValue:specifier:)
                                                                    get:@selector(readPreferenceValue:)
                                                                 detail:nil
                                                                   cell:PSSwitchCell
                                                                   edit:nil];
        [removeTags setProperty:@"removeExtraTags" forKey:@"key"];
        [removeTags setProperty:@"playpass.direct.fmprefs" forKey:@"defaults"];
        [removeTags setProperty:@YES forKey:@"default"];
        [removeTags setProperty:@"removeExtraTags" forKey:@"id"];
        [removeTags setProperty:@"playpass.direct.fmprefs-updated" forKey:@"PostNotification"];
        [specs addObject:removeTags];
        
        // cache section
        PSSpecifier *cacheGroup = [PSSpecifier groupSpecifierWithName:@"Scrobble Cache"];
        [cacheGroup setProperty:@"Scrobbles are automatically cached when internet is unavailable. Use retry to submit them later." forKey:@"footerText"];
        [specs addObject:cacheGroup];
        
        PSSpecifier *cachedScrobbles = [PSSpecifier preferenceSpecifierNamed:@"Cached Scrobbles"
                                                                      target:self
                                                                         set:nil
                                                                         get:@selector(getCachedScrobblesCount:)
                                                                      detail:nil
                                                                        cell:PSButtonCell
                                                                        edit:nil];
        [cachedScrobbles setProperty:@"cachedScrobblesCount" forKey:@"id"];
        cachedScrobbles.buttonAction = @selector(showCachedScrobbles);
        [specs addObject:cachedScrobbles];
        
        PSSpecifier *retryCache = [PSSpecifier preferenceSpecifierNamed:@"Retry Cached Scrobbles"
                                                                 target:self
                                                                    set:nil
                                                                    get:nil
                                                                 detail:nil
                                                                   cell:PSButtonCell
                                                                   edit:nil];
        retryCache.buttonAction = @selector(retryCachedScrobbles);
        [specs addObject:retryCache];
        
        PSSpecifier *lastRetry = [PSSpecifier preferenceSpecifierNamed:@"Last Retry Status"
                                                                target:self
                                                                   set:nil
                                                                   get:@selector(getLastCacheRetryStatus:)
                                                                detail:nil
                                                                  cell:PSTitleValueCell
                                                                  edit:nil];
        [lastRetry setProperty:@"lastCacheRetryStatus" forKey:@"id"];
        [specs addObject:lastRetry];
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    id value = [defaults objectForKey:[specifier propertyForKey:@"key"]];
    if (!value) {
        value = [specifier propertyForKey:@"default"];
    }
    return value;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    [defaults setObject:value forKey:[specifier propertyForKey:@"key"]];
    [defaults synchronize];
    
    NSString *notification = [specifier propertyForKey:@"PostNotification"];
    if (notification) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)notification, NULL, NULL, YES);
    }
}

- (NSString*)getSelectedAppsDisplay:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSArray *selectedApps = [defaults arrayForKey:@"selectedApps"];
    
    if (!selectedApps || [selectedApps count] == 0) {
        return @"None selected";
    }
    
    NSMutableArray *names = [[NSMutableArray alloc] init];
    for (NSString *bundleID in selectedApps) {
        if ([bundleID isEqualToString:@"com.apple.Music"]) {
            [names addObject:@"Apple Music"];
        } else if ([bundleID isEqualToString:@"com.spotify.client"]) {
            [names addObject:@"Spotify"];
        } else if ([bundleID isEqualToString:@"com.google.ios.youtubemusic"]) {
            [names addObject:@"YouTube Music"];
        } else {
            [names addObject:bundleID];
        }
    }
    
    if ([names count] <= 2) {
        return [names componentsJoinedByString:@", "];
    } else {
        return [NSString stringWithFormat:@"%lu apps selected", (unsigned long)[names count]];
    }
}

- (void)showAppPicker {
    // call main controller's showAppPicker
    if (self.mainController && [self.mainController respondsToSelector:@selector(showAppPicker)]) {
        [self.mainController performSelector:@selector(showAppPicker)];
    }
}

- (NSString*)getCachedScrobblesCount:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSInteger count = [defaults integerForKey:@"cachedScrobblesCount"];
    return [NSString stringWithFormat:@"%ld", (long)count];
}

- (void)showCachedScrobbles {
    DirectFMCachedScrobblesViewController *cachedVC = [[DirectFMCachedScrobblesViewController alloc] init];
    [self.navigationController pushViewController:cachedVC animated:YES];
}

- (void)retryCachedScrobbles {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSInteger cachedCount = [defaults integerForKey:@"cachedScrobblesCount"];
    
    if (cachedCount == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Cached Scrobbles" 
                                                                       message:@"There are no cached scrobbles to retry." 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Retry Cached Scrobbles" 
                                                                   message:[NSString stringWithFormat:@"Retry %ld cached scrobbles?", (long)cachedCount] 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Retry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("playpass.direct.fm-retry-cache"), NULL, NULL, YES);
        
        [defaults setObject:@"Retrying..." forKey:@"lastCacheRetryStatus"];
        [defaults synchronize];
        [self reloadSpecifier:[self specifierForID:@"lastCacheRetryStatus"]];
        [self reloadSpecifier:[self specifierForID:@"cachedScrobblesCount"]];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString*)getLastCacheRetryStatus:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSString *status = [defaults stringForKey:@"lastCacheRetryStatus"];
    return status ?: @"Never";
}

@end

