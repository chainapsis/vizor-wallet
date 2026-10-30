#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Geometry belongs to this engine's view, never a global/main screen.
@interface MobileNavigationGeometryHandler : NSObject <FlutterStreamHandler>
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger
          viewControllerProvider:(UIViewController *_Nullable (^)(void))provider;
@end

NS_ASSUME_NONNULL_END
