#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <AltList/LSApplicationProxy.h>
#import <AltList/ATLApplicationListControllerBase.h>

@interface SCRUBRootListController : PSListController
@property (atomic) bool daemonRunning;
@property (strong, nonatomic) NSMutableArray *selectedAppBundleIDs;
- (void)showAppPicker;
- (void)showSelectedAppsPopup;
- (NSString *)getAppNameFromBundleID:(NSString *)bundleID;
@end

// app picker using AltList
@interface SCRUBAppPickerController : ATLApplicationListControllerBase
@property (weak, nonatomic) SCRUBRootListController *scrubbleRootController;
@end
