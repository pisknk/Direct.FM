#import "DirectFMStatusViewController.h"
#import "DirectFMScrobbledTracksViewController.h"
#import <Preferences/PSSpecifier.h>
#import <libroot.h>
#import "include/NSTask.h"

@implementation DirectFMStatusViewController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[NSMutableArray alloc] init];
        
        // daemon section
        PSSpecifier *daemonGroup = [PSSpecifier groupSpecifierWithName:@"Daemon"];
        [specs addObject:daemonGroup];
        
        PSSpecifier *daemonStatus = [PSSpecifier preferenceSpecifierNamed:@"Daemon Status"
                                                                   target:self
                                                                      set:nil
                                                                      get:@selector(daemonStatus:)
                                                                   detail:nil
                                                                     cell:PSTitleValueCell
                                                                     edit:nil];
        [daemonStatus setProperty:@"daemonStatus" forKey:@"id"];
        [specs addObject:daemonStatus];
        
        PSSpecifier *daemonToggle = [PSSpecifier preferenceSpecifierNamed:@"Loading..."
                                                                   target:self
                                                                      set:nil
                                                                      get:nil
                                                                   detail:nil
                                                                     cell:PSButtonCell
                                                                     edit:nil];
        [daemonToggle setProperty:@"daemonToggle" forKey:@"id"];
        daemonToggle.buttonAction = @selector(toggleDaemon);
        [specs addObject:daemonToggle];
        
        // scrobbles section
        PSSpecifier *scrobblesGroup = [PSSpecifier groupSpecifierWithName:@"Scrobbles"];
        [specs addObject:scrobblesGroup];
        
        PSSpecifier *totalScrobbles = [PSSpecifier preferenceSpecifierNamed:@"Total Scrobbles"
                                                                     target:self
                                                                        set:nil
                                                                        get:@selector(getScrobbleCount:)
                                                                     detail:nil
                                                                       cell:PSButtonCell
                                                                       edit:nil];
        [totalScrobbles setProperty:@"scrobbleCount" forKey:@"id"];
        totalScrobbles.buttonAction = @selector(showScrobbledTracks);
        [specs addObject:totalScrobbles];
        
        PSSpecifier *lastScrobbled = [PSSpecifier preferenceSpecifierNamed:@"Last Scrobbled"
                                                                    target:self
                                                                       set:nil
                                                                       get:@selector(getLastScrobbledTrack:)
                                                                    detail:nil
                                                                      cell:PSTitleValueCell
                                                                      edit:nil];
        [lastScrobbled setProperty:@"lastScrobbledTrack" forKey:@"id"];
        [specs addObject:lastScrobbled];
        
        PSSpecifier *currentApp = [PSSpecifier preferenceSpecifierNamed:@"Current App"
                                                                 target:self
                                                                    set:nil
                                                                    get:@selector(getCurrentPlayingApp:)
                                                                 detail:nil
                                                                   cell:PSTitleValueCell
                                                                   edit:nil];
        [currentApp setProperty:@"currentPlayingApp" forKey:@"id"];
        [specs addObject:currentApp];
        
        // debug section
        PSSpecifier *debugGroup = [PSSpecifier groupSpecifierWithName:@"Debug"];
        [specs addObject:debugGroup];
        
        PSSpecifier *checkStatus = [PSSpecifier preferenceSpecifierNamed:@"Check Full Scrobble Status"
                                                                  target:self
                                                                     set:nil
                                                                     get:nil
                                                                  detail:nil
                                                                    cell:PSButtonCell
                                                                    edit:nil];
        checkStatus.buttonAction = @selector(checkScrobbleStatus);
        [specs addObject:checkStatus];
        
        PSSpecifier *resetCounter = [PSSpecifier preferenceSpecifierNamed:@"Reset Debug Counter"
                                                                   target:self
                                                                      set:nil
                                                                      get:nil
                                                                   detail:nil
                                                                     cell:PSButtonCell
                                                                     edit:nil];
        resetCounter.buttonAction = @selector(resetScrobbleCount);
        [specs addObject:resetCounter];
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadDaemonStatus];
}

- (NSString*)daemonStatus:(PSSpecifier*)sender {
    @try {
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

        if (!output || [[output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""]) {
            self.daemonRunning = NO;
            return @"Stopped";
        }
        
        self.daemonRunning = ![output hasPrefix:@"-"];
        [self reloadDaemonToggleLabel];
        return (self.daemonRunning ? @"Running" : @"Stopped");
    }
    @catch(NSException *e) {
        NSLog(@"Exception: %@", e.reason);
    }

    return @"Stopped";
}

- (void)reloadDaemonToggleLabel {
    PSSpecifier *daemonToggle = [self specifierForID:@"daemonToggle"];
    if (daemonToggle) {
        daemonToggle.name = self.daemonRunning ? @"Stop Daemon" : @"Start Daemon";
        [self reloadSpecifier:daemonToggle];
    }
}

- (void)reloadDaemonStatus {
    PSSpecifier *daemonStatus = [self specifierForID:@"daemonStatus"];
    if (daemonStatus) [self reloadSpecifier:daemonStatus];
    [self reloadDaemonToggleLabel];
}

- (void)toggleDaemon {
    @try {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = JBROOT_PATH_NSSTRING(@"/bin/sh");
        
        if (self.daemonRunning) {
            task.arguments = @[@"-c", [NSString stringWithFormat:@"%@ unload %@", JBROOT_PATH_NSSTRING(@"/usr/bin/launchctl"), JBROOT_PATH_NSSTRING(@"/Library/LaunchDaemons/playpass.direct.fm.plist")]];
        } else {
            task.arguments = @[@"-c", [NSString stringWithFormat:@"%@ load %@", JBROOT_PATH_NSSTRING(@"/usr/bin/launchctl"), JBROOT_PATH_NSSTRING(@"/Library/LaunchDaemons/playpass.direct.fm.plist")]];
        }
        
        [task launch];
        [task waitUntilExit];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self reloadDaemonStatus];
        });
    }
    @catch(NSException *e) {
        NSLog(@"Exception toggling daemon: %@", e.reason);
    }
}

- (NSString*)getScrobbleCount:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSInteger count = [defaults integerForKey:@"scrobbleCount"];
    return [NSString stringWithFormat:@"%ld", (long)count];
}

- (void)showScrobbledTracks {
    DirectFMScrobbledTracksViewController *tracksVC = [[DirectFMScrobbledTracksViewController alloc] init];
    [self.navigationController pushViewController:tracksVC animated:YES];
}

- (NSString*)getLastScrobbledTrack:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSString *lastTrack = [defaults stringForKey:@"lastScrobbledTrack"];
    return lastTrack ?: @"None";
}

- (NSString*)getCurrentPlayingApp:(PSSpecifier*)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    NSString *app = [defaults stringForKey:@"currentPlayingApp"];
    return app ?: @"None";
}

- (void)checkScrobbleStatus {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
    
    NSString *username = [defaults stringForKey:@"username"];
    NSString *lastTrack = [defaults stringForKey:@"lastScrobbledTrack"];
    NSString *currentApp = [defaults stringForKey:@"currentPlayingApp"];
    NSInteger scrobbleCount = [defaults integerForKey:@"scrobbleCount"];
    NSInteger cachedCount = [defaults integerForKey:@"cachedScrobblesCount"];
    NSArray *selectedApps = [defaults arrayForKey:@"selectedApps"];
    
    NSString *message = [NSString stringWithFormat:
        @"Username: %@\n"
        @"Daemon: %@\n"
        @"Total Scrobbles: %ld\n"
        @"Cached: %ld\n"
        @"Last Track: %@\n"
        @"Current App: %@\n"
        @"Selected Apps: %lu",
        username ?: @"Not set",
        self.daemonRunning ? @"Running" : @"Stopped",
        (long)scrobbleCount,
        (long)cachedCount,
        lastTrack ?: @"None",
        currentApp ?: @"None",
        (unsigned long)[selectedApps count]
    ];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scrobble Status" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetScrobbleCount {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Counter" 
                                                                   message:@"Reset the debug scrobble counter to 0?" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
        [defaults setInteger:0 forKey:@"scrobbleCount"];
        [defaults removeObjectForKey:@"lastScrobbledTrack"];
        [defaults synchronize];
        [self reloadSpecifier:[self specifierForID:@"scrobbleCount"]];
        [self reloadSpecifier:[self specifierForID:@"lastScrobbledTrack"]];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

