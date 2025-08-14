#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface SCRUBRootListController : PSListController
@property (atomic) bool daemonRunning;
@property (strong, nonatomic) NSArray *availableApps;
@property (strong, nonatomic) NSMutableArray *selectedAppBundleIDs;
- (void)showAppPicker;
- (void)showSelectedAppsPopup;
- (NSArray *)getInstalledMusicApps;
- (NSString *)getAppNameFromBundleID:(NSString *)bundleID;
@end

// separate controller for app selection
@interface SCRUBAppPickerListController : PSListController
@property (strong, nonatomic) NSArray *availableApps;
@property (strong, nonatomic) NSMutableArray *selectedAppBundleIDs;
@property (weak, nonatomic) SCRUBRootListController *rootController;
- (NSArray *)getInstalledMusicApps;
- (NSString *)getAppNameFromBundleID:(NSString *)bundleID;
- (void)saveSelectedApps;
@end
