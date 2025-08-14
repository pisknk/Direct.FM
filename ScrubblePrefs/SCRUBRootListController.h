#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface SCRUBRootListController : PSListController
@property (atomic) bool daemonRunning;
@property (strong, nonatomic) NSArray *availableApps;
@property (strong, nonatomic) NSMutableArray *selectedAppBundleIDs;
- (void)showAppPicker;
- (NSArray *)getInstalledMusicApps;
- (NSString *)getAppNameFromBundleID:(NSString *)bundleID;
@end
