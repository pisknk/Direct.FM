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
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
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

@end
