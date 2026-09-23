#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface MatchShotResult : NSObject
@property (nonatomic, copy) NSString *guidance;
@property (nonatomic) NSInteger inlierCount;
@property (nonatomic) BOOL confident;
@end

@interface MatchShotBridge : NSObject
+ (MatchShotResult *)compareBefore:(UIImage *)before after:(UIImage *)after;
@end
NS_ASSUME_NONNULL_END
