#import "MobileNavigationGeometryHandler.h"

@interface MobileNavigationGeometryProbe : UIView
@property(nonatomic, copy) void (^geometryChanged)(void);
@end

@implementation MobileNavigationGeometryProbe
- (void)layoutSubviews {
  [super layoutSubviews];
  if (self.geometryChanged) self.geometryChanged();
}
- (void)safeAreaInsetsDidChange {
  [super safeAreaInsetsDidChange];
  if (self.geometryChanged) self.geometryChanged();
}
@end

static NSDictionary *NavigationRect(CGRect rect) {
  return @{ @"x": @(rect.origin.x), @"y": @(rect.origin.y),
            @"width": @(rect.size.width), @"height": @(rect.size.height) };
}

@implementation MobileNavigationGeometryHandler {
  UIViewController *_Nullable (^_provider)(void);
  FlutterEventSink _sink;
  __weak UIView *_host;
  MobileNavigationGeometryProbe *_probe;
  id _traitRegistration;
  id<UIInteraction> _hingeInteraction;
  id _foregroundObserver;
  NSDictionary *_lastSnapshot;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger
          viewControllerProvider:(UIViewController *_Nullable (^)(void))provider {
  self = [super init];
  if (self) {
    _provider = [provider copy];
    __weak typeof(self) weakSelf = self;
    FlutterMethodChannel *method = [FlutterMethodChannel
        methodChannelWithName:@"com.zcash.wallet/mobile_navigation_geometry"
              binaryMessenger:messenger];
    [method setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
      if (![call.method isEqualToString:@"getGeometry"]) {
        result(FlutterMethodNotImplemented);
        return;
      }
      [weakSelf attachToCurrentView];
      result([weakSelf snapshot]);
    }];
    [[FlutterEventChannel eventChannelWithName:@"com.zcash.wallet/mobile_navigation_geometry/events"
                              binaryMessenger:messenger] setStreamHandler:self];
  }
  return self;
}

- (void)detach {
  if (_traitRegistration && _host) {
    if (@available(iOS 17.0, *)) [_host unregisterForTraitChanges:_traitRegistration];
  }
  _traitRegistration = nil;
  if (_hingeInteraction) [_host removeInteraction:_hingeInteraction];
  _hingeInteraction = nil;
  [_probe removeFromSuperview];
  _probe = nil;
  _host = nil;
}

- (void)attachToCurrentView {
  UIView *view = _provider().viewIfLoaded;
  if (!_sink || !view || view == _host) return;
  [self detach];
  _host = view;
  _probe = [[MobileNavigationGeometryProbe alloc] initWithFrame:view.bounds];
  _probe.userInteractionEnabled = NO;
  _probe.accessibilityElementsHidden = YES;
  _probe.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  __weak typeof(self) weakSelf = self;
  _probe.geometryChanged = ^{ [weakSelf publish]; };
  [view addSubview:_probe];
  // Compile-time SDK gating keeps Xcode 26.6 builds usable. Only the
  // 27.1+ SDK opts into these public APIs; older builds keep bottom tabs.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
  if (@available(iOS 27.1, *)) {
    _hingeInteraction = [[UIHingeInteraction alloc] initWithUpdateHandler:
        ^(UIHingeInteraction *interaction, UIHingeInteractionUpdate *update) {
          [weakSelf publish];
        }];
    [view addInteraction:_hingeInteraction];
    _traitRegistration = [view registerForTraitChanges:
        UITraitCollection.systemTraitsAffectingVerticalBarEdge
        withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) {
          [weakSelf publish];
        }];
  }
#endif
}

- (NSDictionary *)snapshot {
  UIView *view = _provider().viewIfLoaded;
  if (!view.window || view.bounds.size.width <= 0 || view.bounds.size.height <= 0) return nil;
  NSString *edge = @"none";
  BOOL supported = NO;
  NSMutableArray *occlusions = [NSMutableArray array];
  NSMutableArray *divisions = [NSMutableArray array];
  CGRect barRect = CGRectZero;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
  if (@available(iOS 27.1, *)) {
    supported = YES;
    UIVerticalBarEdge preferred = view.traitCollection.verticalBarEdge;
    if (preferred != UIVerticalBarEdgeUnspecified) {
      // The system selects the edge. A larger inset can instead belong to
      // a hinge or another obstruction, so it must not override this trait.
      BOOL rtl = view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
      BOOL left = (preferred == UIVerticalBarEdgeLeading) != rtl;
      edge = left ? @"left" : @"right";
    }
    UIView *reader = _probe ?: view;
    if (preferred != UIVerticalBarEdgeUnspecified) {
      UIRectEdge physicalEdge = [edge isEqualToString:@"left"] ? UIRectEdgeLeft : UIRectEdgeRight;
      UIViewLayoutRegion *region = [UIViewLayoutRegion layoutRegionForBarOnEdge:physicalEdge extent:64];
      barRect = [reader convertRect:[reader layoutGuideForLayoutRegion:region].layoutFrame toView:view];
    }
    for (UIViewReservedRegion *region in [reader reservedRegionsOfKind:UIViewReservedRegionKind.divisionRegionKind]) {
      if (region.active) [divisions addObject:NavigationRect([reader convertRect:region.frame toView:view])];
    }
    for (UIViewReservedRegion *region in [reader reservedRegionsOfKind:UIViewReservedRegionKind.occlusionRegionKind]) {
      // frame already includes the system's interaction margins.
      if (region.active) [occlusions addObject:NavigationRect([reader convertRect:region.frame toView:view])];
    }
  }
#endif
  UIWindowScene *scene = view.window.windowScene;
  CGRect status = scene.statusBarManager.statusBarFrame;
  if (!CGRectIsEmpty(status)) {
    CGRect localStatus = [view convertRect:status fromCoordinateSpace:scene.coordinateSpace];
    [occlusions addObject:NavigationRect(localStatus)];
  }
  return @{ @"supported": @(supported), @"edge": edge,
            @"bounds": NavigationRect(view.bounds),
            @"safeRect": NavigationRect(view.safeAreaLayoutGuide.layoutFrame),
            @"occlusions": occlusions, @"divisions": divisions,
            @"barRect": NavigationRect(barRect) };
}

- (void)publish {
  if (!_sink) return;
  NSDictionary *snapshot = [self snapshot];
  if (snapshot && ![snapshot isEqual:_lastSnapshot]) {
    _lastSnapshot = snapshot;
    _sink(snapshot);
  }
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  _sink = [events copy];
  _lastSnapshot = nil;
  [self attachToCurrentView];
  [self publish];
  __weak typeof(self) weakSelf = self;
  _foregroundObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
      usingBlock:^(NSNotification *notification) {
        [weakSelf attachToCurrentView];
        [weakSelf publish];
      }];
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  _sink = nil;
  _lastSnapshot = nil;
  [self detach];
  if (_foregroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:_foregroundObserver];
  _foregroundObserver = nil;
  return nil;
}

- (void)dealloc {
  [self detach];
  if (_foregroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:_foregroundObserver];
}
@end
