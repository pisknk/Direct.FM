#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <MediaRemote/MediaRemote.h>
#import "Constants.h"


@interface Scrobbler : NSObject

@property (strong, atomic) NSString *token;
@property (strong, atomic) NSString *apiKey;
@property (strong, atomic) NSString *apiSecret;
@property (strong, atomic) NSString *username;
@property (strong, atomic) NSString *password;
@property (strong, atomic) NSArray<NSString *> *selectedApps;
@property (atomic) float scrobbleAfter;
@property (atomic) bool loggedIn;
-(void) registerObserver;
-(void) musicDidChange:(NSNotification*)notification;
-(void) checkCurrentlyPlayingMusic;
-(void)loadToken;
-(void) cacheScrobble:(NSDictionary*)scrobbleData;
-(void) retryCachedScrobbles;
-(NSInteger) getCachedScrobblesCount;
-(void) saveScrobbleToHistory:(NSString*)track artist:(NSString*)artist album:(NSString*)album timestamp:(NSString*)timestamp;
-(NSArray*) loadScrobbleHistory;
@end