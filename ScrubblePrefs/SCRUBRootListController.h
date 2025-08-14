#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface SCRUBRootListController : PSListController
@property (atomic) bool daemonRunning;
@property (strong, nonatomic) NSMutableArray *selectedAppBundleIDs;
- (void)showAppPicker;
- (void)showSelectedAppsPopup;
- (NSString *)getAppNameFromBundleID:(NSString *)bundleID;
@end

// forward declarations to avoid header dependency issues
@class LSApplicationProxy;

// app picker using AltList with runtime loading
@interface SCRUBAppPickerController : PSListController
@property (weak, nonatomic) SCRUBRootListController *scrubbleRootController;
@property (strong, nonatomic) NSMutableSet *selectedApplications;
@property (assign, nonatomic) BOOL showIdentifiersAsSubtitle;
@property (assign, nonatomic) BOOL showSearchBar;
@property (assign, nonatomic) BOOL hideSearchBarWhileScrolling;
- (BOOL)shouldShowApplication:(LSApplicationProxy *)application;
@end
