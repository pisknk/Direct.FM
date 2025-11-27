#import "DirectFMCachedScrobblesViewController.h"
#import <UIKit/UIKit.h>

@interface DirectFMCachedScrobbleCell : UITableViewCell
@property (nonatomic, strong) UILabel *trackLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UILabel *albumLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation DirectFMCachedScrobbleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // track label
        self.trackLabel = [[UILabel alloc] init];
        self.trackLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.trackLabel.font = [UIFont boldSystemFontOfSize:16];
        self.trackLabel.numberOfLines = 1;
        [self.contentView addSubview:self.trackLabel];
        
        // artist label
        self.artistLabel = [[UILabel alloc] init];
        self.artistLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.artistLabel.font = [UIFont systemFontOfSize:14];
        self.artistLabel.textColor = [UIColor grayColor];
        self.artistLabel.numberOfLines = 1;
        [self.contentView addSubview:self.artistLabel];
        
        // album label
        self.albumLabel = [[UILabel alloc] init];
        self.albumLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.albumLabel.font = [UIFont systemFontOfSize:12];
        self.albumLabel.textColor = [UIColor lightGrayColor];
        self.albumLabel.numberOfLines = 1;
        [self.contentView addSubview:self.albumLabel];
        
        // status label (shows "Pending" or "Failed")
        self.statusLabel = [[UILabel alloc] init];
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.statusLabel.font = [UIFont systemFontOfSize:11];
        self.statusLabel.textColor = [UIColor orangeColor];
        self.statusLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.statusLabel];
        
        // layout constraints
        [NSLayoutConstraint activateConstraints:@[
            // track label
            [self.trackLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.trackLabel.trailingAnchor constraintEqualToAnchor:self.statusLabel.leadingAnchor constant:-8],
            [self.trackLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            
            // artist label
            [self.artistLabel.leadingAnchor constraintEqualToAnchor:self.trackLabel.leadingAnchor],
            [self.artistLabel.trailingAnchor constraintEqualToAnchor:self.trackLabel.trailingAnchor],
            [self.artistLabel.topAnchor constraintEqualToAnchor:self.trackLabel.bottomAnchor constant:4],
            
            // album label
            [self.albumLabel.leadingAnchor constraintEqualToAnchor:self.trackLabel.leadingAnchor],
            [self.albumLabel.trailingAnchor constraintEqualToAnchor:self.trackLabel.trailingAnchor],
            [self.albumLabel.topAnchor constraintEqualToAnchor:self.artistLabel.bottomAnchor constant:2],
            [self.albumLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],
            
            // status label
            [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.statusLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.statusLabel.widthAnchor constraintEqualToConstant:80]
        ]];
    }
    return self;
}

@end

@implementation DirectFMCachedScrobblesViewController {
    NSArray *_cachedScrobbles;
    UITableView *_tableView;
}

- (void)loadView {
    // create our own view instead of using PSListController's
    self.view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor whiteColor];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cached Scrobbles";
    
    // create table view
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.rowHeight = 80;
    _tableView.allowsSelection = NO;
    if (@available(iOS 13.0, *)) {
        _tableView.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        _tableView.backgroundColor = [UIColor whiteColor];
    }
    [self.view addSubview:_tableView];
    
    // register cell
    [_tableView registerClass:[DirectFMCachedScrobbleCell class] forCellReuseIdentifier:@"CachedScrobbleCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // ensure table view frame is correct
    _tableView.frame = self.view.bounds;
    // reload cached scrobbles when view appears
    [self loadCachedScrobbles];
    [_tableView reloadData];
    NSLog(@"[Direct.FM] Cached viewWillAppear - table view frame: %@, cached count: %lu", NSStringFromCGRect(_tableView.frame), (unsigned long)[_cachedScrobbles count]);
    
    // show/hide empty state
    if ([_cachedScrobbles count] == 0) {
        // check if empty label already exists
        UILabel *emptyLabel = nil;
        for (UIView *subview in self.view.subviews) {
            if ([subview isKindOfClass:[UILabel class]] && [((UILabel*)subview).text isEqualToString:@"No cached scrobbles"]) {
                emptyLabel = (UILabel*)subview;
                break;
            }
        }
        
        if (!emptyLabel) {
            emptyLabel = [[UILabel alloc] init];
            emptyLabel.text = @"No cached scrobbles";
            emptyLabel.textAlignment = NSTextAlignmentCenter;
            emptyLabel.textColor = [UIColor grayColor];
            emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addSubview:emptyLabel];
            
            [NSLayoutConstraint activateConstraints:@[
                [emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
                [emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
            ]];
        }
        emptyLabel.hidden = NO;
    } else {
        // hide empty label if cached scrobbles exist
        for (UIView *subview in self.view.subviews) {
            if ([subview isKindOfClass:[UILabel class]] && [((UILabel*)subview).text isEqualToString:@"No cached scrobbles"]) {
                subview.hidden = YES;
                break;
            }
        }
    }
}

- (void)loadCachedScrobbles {
    NSArray *cached = nil;
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // try shared location first (new location)
    NSString *sharedPath = @"/var/mobile/Library/Preferences/";
    NSString *filePath = [sharedPath stringByAppendingPathComponent:@"DirectFMScrobbleCache.plist"];
    
    NSLog(@"[Direct.FM] Checking for cached scrobbles at: %@", filePath);
    BOOL fileExists = [fileManager fileExistsAtPath:filePath];
    NSLog(@"[Direct.FM] File exists: %d", fileExists);
    
    if (fileExists) {
        // check if we can read it
        BOOL isReadable = [fileManager isReadableFileAtPath:filePath];
        NSLog(@"[Direct.FM] File is readable: %d", isReadable);
        
        cached = [NSArray arrayWithContentsOfFile:filePath];
        if (cached && [cached isKindOfClass:[NSArray class]]) {
            NSLog(@"[Direct.FM] Loaded %lu cached scrobbles from shared location", (unsigned long)[cached count]);
        } else {
            NSLog(@"[Direct.FM] Failed to read plist file or invalid format");
            cached = nil;
            
            // check attributes
            NSDictionary *attrs = [fileManager attributesOfItemAtPath:filePath error:&error];
            if (error) {
                NSLog(@"[Direct.FM] Error getting attributes: %@", error);
            } else {
                NSLog(@"[Direct.FM] File attributes: %@", attrs);
            }
        }
    }
    
    // fallback to old location if new location doesn't have data
    if (!cached || [cached count] == 0) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *oldFilePath = [documentsDirectory stringByAppendingPathComponent:@"DirectFMScrobbleCache.plist"];
        
        NSLog(@"[Direct.FM] Checking old location: %@", oldFilePath);
        if ([fileManager fileExistsAtPath:oldFilePath]) {
            cached = [NSArray arrayWithContentsOfFile:oldFilePath];
            if (cached && [cached isKindOfClass:[NSArray class]]) {
                NSLog(@"[Direct.FM] Loaded %lu cached scrobbles from old location", (unsigned long)[cached count]);
                
                // migrate to new location if found in old location
                if ([cached count] > 0) {
                    NSError *copyError = nil;
                    BOOL copied = [fileManager copyItemAtPath:oldFilePath toPath:filePath error:&copyError];
                    if (copied) {
                        NSLog(@"[Direct.FM] Migrated cached scrobbles to shared location");
                    } else {
                        NSLog(@"[Direct.FM] Failed to migrate: %@", copyError);
                    }
                }
            }
        } else {
            NSLog(@"[Direct.FM] Old location file does not exist");
        }
    }
    
    _cachedScrobbles = cached ?: @[];
    
    // fallback to NSUserDefaults if file doesn't exist
    if ([_cachedScrobbles count] == 0) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
        cached = [defaults arrayForKey:@"cachedScrobblesData"];
        if (cached && [cached isKindOfClass:[NSArray class]] && [cached count] > 0) {
            _cachedScrobbles = cached;
            NSLog(@"[Direct.FM] Loaded %lu cached scrobbles from NSUserDefaults", (unsigned long)[_cachedScrobbles count]);
        }
    }
    
    NSLog(@"[Direct.FM] Final cached scrobbles count: %lu", (unsigned long)[_cachedScrobbles count]);
    
    if ([_cachedScrobbles count] == 0) {
        NSLog(@"[Direct.FM] WARNING: No cached scrobbles found. Checked paths: %@ and old location and NSUserDefaults", filePath);
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSLog(@"[Direct.FM] Cached numberOfRowsInSection called, returning: %lu", (unsigned long)[_cachedScrobbles count]);
    return [_cachedScrobbles count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DirectFMCachedScrobbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CachedScrobbleCell"];
    if (!cell) {
        cell = [[DirectFMCachedScrobbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CachedScrobbleCell"];
    }
    
    NSDictionary *cachedScrobble = _cachedScrobbles[indexPath.row];
    
    // extract track info from cached scrobble format: "track[0]", "artist[0]", etc.
    NSString *track = cachedScrobble[@"track[0]"] ?: cachedScrobble[@"track"] ?: @"Unknown Track";
    NSString *artist = cachedScrobble[@"artist[0]"] ?: cachedScrobble[@"artist"] ?: @"Unknown Artist";
    NSString *album = cachedScrobble[@"album[0]"] ?: cachedScrobble[@"album"] ?: @"Unknown Album";
    
    cell.trackLabel.text = track;
    cell.artistLabel.text = artist;
    cell.albumLabel.text = album;
    cell.statusLabel.text = @"Pending";
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *cachedScrobble = _cachedScrobbles[indexPath.row];
        
        // remove from array
        NSMutableArray *mutableCached = [_cachedScrobbles mutableCopy];
        [mutableCached removeObjectAtIndex:indexPath.row];
        _cachedScrobbles = [mutableCached copy];
        
        // save updated cache to disk
        NSString *sharedPath = @"/var/mobile/Library/Preferences/";
        NSString *filePath = [sharedPath stringByAppendingPathComponent:@"DirectFMScrobbleCache.plist"];
        [_cachedScrobbles writeToFile:filePath atomically:YES];
        
        // update cache count in preferences
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"playpass.direct.fmprefs"];
        [defaults setInteger:[_cachedScrobbles count] forKey:@"cachedScrobblesCount"];
        [defaults synchronize];
        
        // update table view
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        
        // show alert
        NSString *track = cachedScrobble[@"track[0]"] ?: cachedScrobble[@"track"] ?: @"Unknown Track";
        NSString *artist = cachedScrobble[@"artist[0]"] ?: cachedScrobble[@"artist"] ?: @"Unknown Artist";
        
        if ([UIAlertController class]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Deleted" message:[NSString stringWithFormat:@"Removed \"%@\" by %@ from cache", track, artist] preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:ok];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Deleted" message:[NSString stringWithFormat:@"Removed \"%@\" by %@ from cache", track, artist] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alert show];
        }
    }
}

@end

