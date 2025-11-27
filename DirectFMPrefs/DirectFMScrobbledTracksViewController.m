#import "DirectFMScrobbledTracksViewController.h"
#import <UIKit/UIKit.h>
#import "Constants.h"

@interface DirectFMScrobbledTrackCell : UITableViewCell
@property (nonatomic, strong) UIImageView *albumArtworkView;
@property (nonatomic, strong) UILabel *trackLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UILabel *albumLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@end

@implementation DirectFMScrobbledTrackCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // album artwork
        self.albumArtworkView = [[UIImageView alloc] init];
        self.albumArtworkView.translatesAutoresizingMaskIntoConstraints = NO;
        self.albumArtworkView.contentMode = UIViewContentModeScaleAspectFill;
        self.albumArtworkView.clipsToBounds = YES;
        self.albumArtworkView.layer.cornerRadius = 4.0;
        self.albumArtworkView.backgroundColor = [UIColor lightGrayColor];
        [self.contentView addSubview:self.albumArtworkView];
        
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
        
        // date label
        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.dateLabel.font = [UIFont systemFontOfSize:11];
        self.dateLabel.textColor = [UIColor lightGrayColor];
        self.dateLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.dateLabel];
        
        // layout constraints
        [NSLayoutConstraint activateConstraints:@[
            // album artwork
            [self.albumArtworkView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.albumArtworkView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.albumArtworkView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
            [self.albumArtworkView.widthAnchor constraintEqualToAnchor:self.albumArtworkView.heightAnchor],
            
            // track label
            [self.trackLabel.leadingAnchor constraintEqualToAnchor:self.albumArtworkView.trailingAnchor constant:12],
            [self.trackLabel.trailingAnchor constraintEqualToAnchor:self.dateLabel.leadingAnchor constant:-8],
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
            
            // date label
            [self.dateLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.dateLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.dateLabel.widthAnchor constraintEqualToConstant:80]
        ]];
    }
    return self;
}

@end

@implementation DirectFMScrobbledTracksViewController {
    NSArray *_scrobbledTracks;
    UITableView *_tableView;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // set identifier for Settings search
        PSSpecifier *spec = [[PSSpecifier alloc] init];
        [spec setProperty:@"DirectFMScrobbledTracks" forKey:@"PSIDKey"];
        [spec setProperty:@"DirectFMScrobbledTracks" forKey:@"identifier"];
        [self setSpecifier:spec];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Scrobbled Tracks";
    
    // create table view
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.rowHeight = 80;
    _tableView.allowsSelection = NO;
    [self.view addSubview:_tableView];
    
    // register cell
    [_tableView registerClass:[DirectFMScrobbledTrackCell class] forCellReuseIdentifier:@"ScrobbleCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // reload scrobbled tracks when view appears (in case new scrobbles were added)
    [self loadScrobbledTracks];
    [_tableView reloadData];
    
    // show/hide empty state
    if ([_scrobbledTracks count] == 0) {
        // check if empty label already exists
        UILabel *emptyLabel = nil;
        for (UIView *subview in self.view.subviews) {
            if ([subview isKindOfClass:[UILabel class]] && [((UILabel*)subview).text isEqualToString:@"No scrobbled tracks yet"]) {
                emptyLabel = (UILabel*)subview;
                break;
            }
        }
        
        if (!emptyLabel) {
            emptyLabel = [[UILabel alloc] init];
            emptyLabel.text = @"No scrobbled tracks yet";
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
        // hide empty label if tracks exist
        for (UIView *subview in self.view.subviews) {
            if ([subview isKindOfClass:[UILabel class]] && [((UILabel*)subview).text isEqualToString:@"No scrobbled tracks yet"]) {
                subview.hidden = YES;
                break;
            }
        }
    }
}

- (void)loadScrobbledTracks {
    NSArray *tracks = nil;
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // try shared location first (new location)
    NSString *sharedPath = @"/var/mobile/Library/Preferences/";
    NSString *filePath = [sharedPath stringByAppendingPathComponent:@"DirectFMScrobbleHistory.plist"];
    
    NSLog(@"[Direct.FM] Checking for scrobble history at: %@", filePath);
    BOOL fileExists = [fileManager fileExistsAtPath:filePath];
    NSLog(@"[Direct.FM] File exists: %d", fileExists);
    
    if (fileExists) {
        // check if we can read it
        BOOL isReadable = [fileManager isReadableFileAtPath:filePath];
        NSLog(@"[Direct.FM] File is readable: %d", isReadable);
        
        tracks = [NSArray arrayWithContentsOfFile:filePath];
        NSUInteger trackCount = tracks ? [tracks count] : 0;
        NSLog(@"[Direct.FM] Loaded %lu scrobbled tracks from shared location", (unsigned long)trackCount);
        
        if (!tracks) {
            NSLog(@"[Direct.FM] Failed to read plist file - checking attributes");
            NSDictionary *attrs = [fileManager attributesOfItemAtPath:filePath error:&error];
            if (error) {
                NSLog(@"[Direct.FM] Error getting attributes: %@", error);
            } else {
                NSLog(@"[Direct.FM] File attributes: %@", attrs);
            }
        }
    }
    
    // fallback to old location if new location doesn't have data
    if (!tracks || [tracks count] == 0) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *oldFilePath = [documentsDirectory stringByAppendingPathComponent:@"DirectFMScrobbleHistory.plist"];
        
        NSLog(@"[Direct.FM] Checking old location: %@", oldFilePath);
        if ([fileManager fileExistsAtPath:oldFilePath]) {
            tracks = [NSArray arrayWithContentsOfFile:oldFilePath];
            NSUInteger trackCount = tracks ? [tracks count] : 0;
            NSLog(@"[Direct.FM] Loaded %lu scrobbled tracks from old location", (unsigned long)trackCount);
            
            // migrate to new location if found in old location
            if (tracks && [tracks count] > 0) {
                NSError *copyError = nil;
                BOOL copied = [fileManager copyItemAtPath:oldFilePath toPath:filePath error:&copyError];
                if (copied) {
                    NSLog(@"[Direct.FM] Migrated scrobble history to shared location");
                } else {
                    NSLog(@"[Direct.FM] Failed to migrate: %@", copyError);
                }
            }
        } else {
            NSLog(@"[Direct.FM] Old location file does not exist");
        }
    }
    
    _scrobbledTracks = tracks ?: @[];
    
    NSLog(@"[Direct.FM] Final scrobbled tracks count: %lu", (unsigned long)[_scrobbledTracks count]);
    
    if ([_scrobbledTracks count] == 0) {
        NSLog(@"[Direct.FM] WARNING: No scrobbled tracks found. Checked paths: %@ and old location", filePath);
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_scrobbledTracks count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DirectFMScrobbledTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ScrobbleCell"];
    if (!cell) {
        cell = [[DirectFMScrobbledTrackCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ScrobbleCell"];
    }
    
    NSDictionary *track = _scrobbledTracks[indexPath.row];
    
    cell.trackLabel.text = track[@"track"] ?: @"Unknown Track";
    cell.artistLabel.text = track[@"artist"] ?: @"Unknown Artist";
    cell.albumLabel.text = track[@"album"] ?: @"Unknown Album";
    
    // format date
    NSString *timestamp = track[@"timestamp"];
    if (timestamp && [timestamp length] > 0) {
        NSTimeInterval timeInterval = [timestamp doubleValue];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timeInterval];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        cell.dateLabel.text = [formatter stringFromDate:date];
    } else {
        cell.dateLabel.text = @"";
    }
    
    // load album artwork
    [self loadAlbumArtworkForTrack:track[@"track"] artist:track[@"artist"] album:track[@"album"] intoImageView:cell.albumArtworkView];
    
    return cell;
}

- (void)loadAlbumArtworkForTrack:(NSString*)track artist:(NSString*)artist album:(NSString*)album intoImageView:(UIImageView*)imageView {
    // use last.fm api to get album artwork
    NSString *apiKey = @"73731fecf1e491f98b815044e686d295";
    NSString *encodedArtist = [artist stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *encodedAlbum = [album stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    NSString *urlString = [NSString stringWithFormat:@"https://ws.audioscrobbler.com/2.0/?method=album.getinfo&api_key=%@&artist=%@&album=%@&format=json", apiKey, encodedArtist, encodedAlbum];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (!jsonError && json[@"album"] && json[@"album"][@"image"]) {
                NSArray *images = json[@"album"][@"image"];
                NSString *imageUrl = nil;
                // get largest image (usually last one)
                for (NSDictionary *img in images) {
                    if ([img[@"size"] isEqualToString:@"extralarge"] || [img[@"size"] isEqualToString:@"large"]) {
                        imageUrl = img[@"#text"];
                    }
                }
                if (!imageUrl && [images count] > 0) {
                    imageUrl = images[[images count] - 1][@"#text"];
                }
                
                if (imageUrl && [imageUrl length] > 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self loadImageFromURL:imageUrl intoImageView:imageView];
                    });
                }
            }
        }
    }];
    [task resume];
}

- (void)loadImageFromURL:(NSString*)urlString intoImageView:(UIImageView*)imageView {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            UIImage *image = [UIImage imageWithData:data];
            if (image) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    imageView.image = image;
                });
            }
        }
    }];
    [task resume];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *track = _scrobbledTracks[indexPath.row];
        [self unscrobbleTrack:track];
        
        // remove from array
        NSMutableArray *mutableTracks = [_scrobbledTracks mutableCopy];
        [mutableTracks removeObjectAtIndex:indexPath.row];
        _scrobbledTracks = [mutableTracks copy];
        
        // update table view
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)unscrobbleTrack:(NSDictionary*)track {
    NSString *trackName = track[@"track"];
    NSString *artist = track[@"artist"];
    NSString *timestamp = track[@"timestamp"];
    
    // send notification to daemon to unscrobble
    NSDictionary *userInfo = @{
        @"track": trackName ?: @"",
        @"artist": artist ?: @"",
        @"timestamp": timestamp ?: @""
    };
    
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("playpass.direct.fm-unscrobble"), (__bridge CFDictionaryRef)userInfo, NULL, YES);
    
    // show alert
    if ([UIAlertController class]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Unscrobbled" message:[NSString stringWithFormat:@"Removed \"%@\" by %@ from your scrobbles", trackName, artist] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:ok];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Unscrobbled" message:[NSString stringWithFormat:@"Removed \"%@\" by %@ from your scrobbles", trackName, artist] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
    }
}

- (NSArray *)specifiers {
    return nil; // we're using a custom table view instead
}

@end

