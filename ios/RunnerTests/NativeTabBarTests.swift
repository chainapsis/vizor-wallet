import Flutter
import Testing
import UIKit

@testable import Runner

@MainActor
struct NativeTabBarTests {
  @Test("Invalid snapshots preserve all previously displayed items and selection")
  func atomicSnapshotValidation() throws {
    let fixture = NativeTabBarFixture()
    let originalItems = try #require(fixture.bar.items)
    let originalSelection = fixture.bar.selectedItem

    var duplicate = fixture.snapshot(ids: ["home", "home"], selected: "home")
    #expect(fixture.update(duplicate) is FlutterError)
    #expect(fixture.bar.items?.first === originalItems.first)
    #expect(fixture.bar.selectedItem === originalSelection)

    duplicate = fixture.snapshot(selected: "missing")
    #expect(fixture.update(duplicate) is FlutterError)
    #expect(fixture.bar.selectedItem === originalSelection)

    var corrupt = fixture.snapshot()
    var items = try #require(corrupt["items"] as? [[String: Any]])
    items[0]["label"] = "Changed before an unknown icon"
    items[1]["iconName"] = "missing"
    corrupt["items"] = items
    #expect(fixture.update(corrupt) is FlutterError)
    #expect(fixture.bar.items?.first?.title == "home")
    #expect(fixture.bar.selectedItem === originalSelection)
  }

  @Test("Tab identities and native images survive label updates, filtering and reordering")
  func stableItemsAndImages() throws {
    let fixture = NativeTabBarFixture()
    let original = try #require(fixture.bar.items)
    let originalImage = try #require(original[2].image)
    #expect(fixture.update(fixture.snapshot(ids: ["settings", "home"], selected: "settings")) == nil)
    #expect(fixture.bar.items?[0] === original[2])
    #expect(fixture.bar.items?[1] === original[0])
    #expect(fixture.bar.selectedItem === original[2])
    #expect(fixture.bar.items?[0].image === originalImage)

    var translated = fixture.snapshot(ids: ["settings", "home"], selected: "settings")
    var items = try #require(translated["items"] as? [[String: Any]])
    items[0]["label"] = "설정"
    translated["items"] = items
    #expect(fixture.update(translated) == nil)
    #expect(fixture.bar.items?[0] === original[2])
    #expect(fixture.bar.items?[0].image === originalImage)
    #expect(fixture.bar.items?[0].title == "설정")
  }

  @Test("Only UIKit selection emits navigation, including re-selection")
  func selectionEvents() throws {
    let fixture = NativeTabBarFixture()
    #expect(fixture.update(fixture.snapshot(selected: "settings")) == nil)
    #expect(fixture.messenger.outgoing.isEmpty)
    let selected = try #require(fixture.bar.selectedItem)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    let events = fixture.messenger.outgoing.filter { $0.method == "select" }
    #expect(events.count == 2)
    #expect(events.allSatisfy {
      ($0.arguments as? [String: Any])?["id"] as? String == "settings"
    })
    fixture.platformView?.tabBar(UITabBar(), didSelect: selected)
    fixture.platformView?.tabBar(fixture.bar, didSelect: UITabBarItem())
    #expect(fixture.messenger.outgoing.count == 2)
  }

  @Test("App theme, direction and hidden state update without replacing the bar")
  func environmentAndVisibility() throws {
    let fixture = NativeTabBarFixture()
    let originalItem = fixture.bar.items?.first
    var args = fixture.snapshot()
    args["brightness"] = "dark"
    args["direction"] = "rtl"
    args["hidden"] = true
    #expect(fixture.update(args) == nil)
    #expect(fixture.host.overrideUserInterfaceStyle == .light)
    #expect(fixture.bar.effectiveUserInterfaceLayoutDirection == .leftToRight)
    #expect(fixture.host.slidingView.isHidden)
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(fixture.bar.items?.first === originalItem)
    #expect(fixture.host.preferredHeight > 0)
    args["hidden"] = false
    #expect(fixture.update(args) == nil)
    #expect(!fixture.host.slidingView.isHidden)
    #expect(fixture.host.overrideUserInterfaceStyle == .dark)
    #expect(fixture.bar.effectiveUserInterfaceLayoutDirection == .rightToLeft)
    #expect(fixture.host.isUserInteractionEnabled)
  }

  @Test("Native appearance and template image rendering stay under UIKit control")
  func systemAppearance() throws {
    let fixture = NativeTabBarFixture()
    #expect(fixture.bar.backgroundImage == nil)
    #expect(fixture.bar.shadowImage == nil)
    #expect(fixture.bar.barTintColor == nil)
    let image = try #require(fixture.bar.items?.first?.image)
    #expect(image.renderingMode == .alwaysTemplate)
    #expect(image.size == CGSize(width: 25, height: 25))
    #expect(!fixture.host.clipsToBounds)
    #expect(fixture.host.hitTest(CGPoint(x: -1, y: -1), with: nil) == nil)
  }

  @Test("Layout notifications do not loop when Flutter accepts the native height")
  func heightNegotiation() async throws {
    let fixture = NativeTabBarFixture()
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    await drainMainQueue()
    let heightEvents = fixture.messenger.outgoing.filter { $0.method == "layout" }
    #expect(heightEvents.count == 1)
    let reported = try #require((heightEvents.first?.arguments as? [String: Double])?["height"])
    #expect(reported > 0)
    fixture.host.frame.size.height = reported
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    await drainMainQueue()
    #expect(fixture.messenger.outgoing.filter { $0.method == "layout" }.count == 1)
    #expect(fixture.messenger.call("getHeight") as? Double == reported)
  }

  @Test("Selected icons and titles share the app tint without changing native material")
  func selectedItemTint() throws {
    let fixture = NativeTabBarFixture()
    let item = try #require(fixture.bar.items?.first)
    let originalImage = try #require(item.image)
    let originalTint = fixture.bar.tintColor
    var args = fixture.snapshot()
    args["selectedTintColor"] = 0xFFA83861
    #expect(fixture.update(args) == nil)
    #expect(fixture.bar.tintColor == UIColor(
      red: 168.0 / 255, green: 56.0 / 255, blue: 97.0 / 255, alpha: 1
    ))
    #expect(item.image === originalImage)
    #expect(item.selectedImage?.renderingMode == .alwaysTemplate)
    #expect(item.image?.renderingMode == .alwaysTemplate)
    #expect(fixture.bar.unselectedItemTintColor == nil)
    #expect(fixture.bar.backgroundImage == nil)
    #expect(fixture.bar.shadowImage == nil)
    #expect(fixture.bar.barTintColor == nil)

    args["selectedId"] = "settings"
    #expect(fixture.update(args) == nil)
    #expect(item.image === originalImage)
    args["selectedTintColor"] = 0xFF123456
    #expect(fixture.update(args) == nil)
    #expect(fixture.bar.tintColor == UIColor(
      red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1
    ))
    args.removeValue(forKey: "selectedTintColor")
    #expect(fixture.update(args) == nil)
    #expect(fixture.bar.tintColor == originalTint)
  }

  @Test("Malformed selected tints preserve the existing native color")
  func invalidSelectedTint() throws {
    let fixture = NativeTabBarFixture()
    var args = fixture.snapshot()
    args["selectedTintColor"] = 0xFFA83861
    #expect(fixture.update(args) == nil)
    let tint = fixture.bar.tintColor
    for invalid: Any in [-1, 0x1_0000_0000, 1.5, true, "red"] {
      args["selectedTintColor"] = invalid
      #expect(fixture.update(args) is FlutterError)
      #expect(fixture.bar.tintColor == tint)
    }
  }

  @Test("Platform-view destruction removes the channel and pending callback owner")
  func disposal() {
    let fixture = NativeTabBarFixture()
    #expect(fixture.messenger.hasHandler)
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    fixture.platformView = nil
    #expect(!fixture.messenger.hasHandler)
    #expect(fixture.host.tabBar.delegate == nil)
    #expect(fixture.host.onHeightChanged == nil)
    #expect(fixture.host.onGeometryChanged == nil)
    #expect(fixture.host.onAttachmentChanged == nil)
    #expect(fixture.host.onLayoutCompleted == nil)
  }

  @Test("Entrance and exit use native durations and gate input plus accessibility")
  func animatedPresentationGate() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    #expect(animator.animations.count == 1)
    let entrance = try #require(animator.animations.last)
    #expect(entrance.duration == 0.180)
    #expect(entrance.timing.controlPoint1 == CGPoint(x: 0.2, y: 0.8))
    #expect(entrance.timing.controlPoint2 == CGPoint(x: 0.2, y: 1))
    #expect(entrance.start.ty > 0)
    #expect(entrance.target == .identity)
    #expect(!fixture.host.slidingView.isHidden)
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(!fixture.bar.isUserInteractionEnabled)
    #expect(fixture.host.accessibilityElementsHidden)
    let item = try #require(fixture.bar.selectedItem)
    fixture.platformView?.tabBar(fixture.bar, didSelect: item)
    #expect(fixture.selectionEvents.isEmpty)
    entrance.finish()
    let ready = fixture.presentation
    #expect(ready["interactive"] as? Bool == true)
    #expect(fixture.host.isUserInteractionEnabled)
    #expect(!fixture.host.accessibilityElementsHidden)
    fixture.platformView?.tabBar(fixture.bar, didSelect: item)
    let event = try #require(fixture.selectionEvents.last?.arguments as? [String: Any])
    #expect(event["visibilityEpoch"] as? Int64 == 0)
    #expect(event["revision"] as? Int64 == ready["revision"] as? Int64)

    var hidden = fixture.snapshot()
    hidden["hidden"] = true
    hidden["visibilityEpoch"] = 1
    #expect(fixture.update(hidden) == nil)
    #expect(fixture.presentation["interactive"] as? Bool == false)
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(fixture.host.accessibilityElementsHidden)
    #expect(!fixture.host.slidingView.isHidden)
    fixture.platformView?.tabBar(fixture.bar, didSelect: item)
    #expect(fixture.selectionEvents.count == 1)
    let exit = try #require(animator.animations.last)
    #expect(exit.duration == 0.140)
    #expect(exit.timing.controlPoint1 == CGPoint(x: 0.3, y: 0))
    #expect(exit.timing.controlPoint2 == CGPoint(x: 0.8, y: 0.7))
    #expect(exit.target.ty >= fixture.host.bounds.height)
    exit.finish()
    #expect(fixture.host.slidingView.isHidden)
    #expect(fixture.presentation["visibilityEpoch"] as? Int64 == 1)
  }

  @Test("Exit freezes shown content and entrance applies only the latest validated snapshot")
  func pendingHiddenContent() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    animator.animations.last?.finish()
    let home = try #require(fixture.bar.items?.first)
    var pending = fixture.snapshot(selected: "settings")
    pending["hidden"] = true
    pending["visibilityEpoch"] = 1
    pending["brightness"] = "dark"
    pending["selectedTintColor"] = 0xFF123456
    #expect(fixture.update(pending) == nil)
    #expect(fixture.bar.selectedItem === home)
    #expect(fixture.host.overrideUserInterfaceStyle == .light)
    animator.animations.last?.finish()

    var items = try #require(pending["items"] as? [[String: Any]])
    items[0]["label"] = "Newest home"
    pending["items"] = items
    pending["selectedId"] = "activity"
    #expect(fixture.update(pending) == nil)
    #expect(home.title == "home")
    #expect(fixture.bar.selectedItem === home)
    let hiddenRevision = fixture.presentation["revision"] as? Int64
    var corrupt = pending
    items[0]["iconName"] = "missing"
    corrupt["items"] = items
    #expect(fixture.update(corrupt) is FlutterError)
    #expect(fixture.presentation["revision"] as? Int64 == hiddenRevision)

    pending["hidden"] = false
    pending["visibilityEpoch"] = 2
    #expect(fixture.update(pending) == nil)
    #expect(home.title == "Newest home")
    #expect(fixture.bar.selectedItem?.accessibilityIdentifier == "activity")
    #expect(fixture.host.overrideUserInterfaceStyle == .dark)
    #expect(!fixture.host.isUserInteractionEnabled)
    animator.animations.last?.finish()
    #expect(fixture.presentation["interactive"] as? Bool == true)
  }

  @Test("Rapid reversal starts at the current position and ignores old completions")
  func rapidReversal() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    animator.animations.last?.finish()
    var args = fixture.snapshot()
    args["hidden"] = true
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    let exit = try #require(animator.animations.last)
    exit.progress(to: 0.4)
    let current = fixture.host.slidingView.transform
    args["hidden"] = false
    args["visibilityEpoch"] = 2
    #expect(fixture.update(args) == nil)
    let entrance = try #require(animator.animations.last)
    #expect(exit.cancelled)
    #expect(entrance.start == current)
    #expect(abs(entrance.duration - 0.180 * 0.4) < 0.000001)
    let revision = fixture.presentation["revision"] as? Int64
    exit.completeEvenIfCancelled()
    #expect(!fixture.host.slidingView.isHidden)
    #expect(fixture.presentation["revision"] as? Int64 == revision)
    #expect(fixture.presentation["interactive"] as? Bool == false)
    entrance.finish()
    #expect(fixture.presentation["interactive"] as? Bool == true)
    #expect(fixture.host.slidingView.transform == .identity)
  }

  @Test("Reversing an entrance shortens the exit by its remaining distance")
  func partialExitDuration() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    let entrance = try #require(animator.animations.last)
    entrance.progress(to: 0.75)
    var args = fixture.snapshot()
    args["hidden"] = true
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    let exit = try #require(animator.animations.last)
    #expect(entrance.cancelled)
    #expect(abs(exit.duration - 0.140 * 0.75) < 0.000001)
    #expect(!fixture.host.isUserInteractionEnabled)
    exit.finish()
    #expect(fixture.host.slidingView.isHidden)
    entrance.completeEvenIfCancelled()
    #expect(fixture.host.slidingView.isHidden)
  }

  @Test("A nearly completed reversal settles immediately without an input-blocking tail")
  func negligibleRemainingDistance() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    let entrance = try #require(animator.animations.last)
    entrance.finish()
    var args = fixture.snapshot()
    args["hidden"] = true
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    let exit = try #require(animator.animations.last)
    exit.progress(to: 0.001)
    args["hidden"] = false
    args["visibilityEpoch"] = 2
    #expect(fixture.update(args) == nil)
    #expect(exit.cancelled)
    #expect(animator.animations.count == 2)
    #expect(fixture.host.slidingView.transform == .identity)
    #expect(fixture.presentation["interactive"] as? Bool == true)
    exit.completeEvenIfCancelled()
    #expect(!fixture.host.slidingView.isHidden)
    #expect(fixture.presentation["interactive"] as? Bool == true)
  }

  @Test("Initial visibility waits for attachment and a hidden creation never flashes")
  func attachmentAndInitialHidden() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(
      animator: animator.animate, reducedMotion: false, attached: false
    )
    #expect(animator.animations.isEmpty)
    #expect(fixture.host.slidingView.isHidden)
    #expect(fixture.bar.items?.count == 3)
    fixture.setAttached(true)
    #expect(animator.animations.count == 1)
    #expect(!fixture.host.slidingView.isHidden)
    animator.animations.last?.finish()
    #expect(fixture.presentation["interactive"] as? Bool == true)
    fixture.setAttached(false)
    #expect(fixture.host.slidingView.isHidden)
    #expect(fixture.presentation["interactive"] as? Bool == false)
    fixture.setAttached(true)
    #expect(animator.animations.count == 1)
    #expect(fixture.presentation["interactive"] as? Bool == true)

    let hiddenAnimator = NativeTabBarTestAnimator()
    let hidden = NativeTabBarFixture(
      animator: hiddenAnimator.animate, reducedMotion: false, initiallyHidden: true
    )
    #expect(hiddenAnimator.animations.isEmpty)
    #expect(hidden.host.slidingView.isHidden)
    #expect(hidden.presentation["interactive"] as? Bool == false)
  }

  @Test("Reduce Motion settles the current target immediately and invalidates its old completion")
  func reduceMotionDuringAnimation() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    let entrance = try #require(animator.animations.last)
    entrance.progress(to: 0.3)
    fixture.environment.reducedMotion = true
    fixture.notifications.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    #expect(entrance.cancelled)
    #expect(fixture.presentation["interactive"] as? Bool == true)
    #expect(fixture.host.slidingView.transform == .identity)
    let revision = fixture.presentation["revision"] as? Int64
    entrance.completeEvenIfCancelled()
    #expect(fixture.presentation["revision"] as? Int64 == revision)
    var hidden = fixture.snapshot()
    hidden["hidden"] = true
    hidden["visibilityEpoch"] = 1
    #expect(fixture.update(hidden) == nil)
    #expect(fixture.host.slidingView.isHidden)
    #expect(fixture.presentation["interactive"] as? Bool == false)
    #expect(animator.animations.count == 1)
  }

  @Test("Bad visibility epochs cannot change the accepted target or pending content")
  func visibilityEpochValidation() {
    let fixture = NativeTabBarFixture()
    var args = fixture.snapshot()
    args["visibilityEpoch"] = 3
    #expect(fixture.update(args) == nil)
    for invalid: Any in [-1, 1.5, true, "4", 2] {
      args["visibilityEpoch"] = invalid
      args["hidden"] = true
      #expect(fixture.update(args) is FlutterError)
      #expect(fixture.presentation["visibilityEpoch"] as? Int64 == 3)
      #expect(fixture.presentation["interactive"] as? Bool == true)
    }
  }

  @Test("Animation leaves host geometry and native height stable, and resize retargets safely")
  func animatedGeometryAndDisposal() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    fixture.host.layoutIfNeeded()
    animator.animations.last?.finish()
    let originalFrame = fixture.host.frame
    let originalHeight = fixture.host.preferredHeight
    var hidden = fixture.snapshot()
    hidden["hidden"] = true
    hidden["visibilityEpoch"] = 1
    #expect(fixture.update(hidden) == nil)
    let exit = try #require(animator.animations.last)
    exit.progress(to: 0.4)
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    #expect(fixture.host.frame == originalFrame)
    #expect(fixture.host.preferredHeight == originalHeight)
    #expect(fixture.bar.frame == CGRect(origin: .zero, size: originalFrame.size))
    fixture.host.frame.size = CGSize(width: 852, height: 80)
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    let resizedExit = try #require(animator.animations.last)
    #expect(exit.cancelled)
    #expect(resizedExit.target.ty >= 80)
    fixture.platformView = nil
    #expect(resizedExit.cancelled)
    #expect(!fixture.messenger.hasHandler)
    #expect(fixture.host.slidingView.isHidden)
    resizedExit.completeEvenIfCancelled()
    #expect(fixture.host.slidingView.isHidden)
  }

  @Test("Cold zero geometry waits for the final native-height handshake and preparation layout")
  func coldZeroGeometryHandshake() throws {
    let animator = NativeTabBarTestAnimator()
    let preparation = NativeTabBarTestPreparationScheduler()
    let fixture = NativeTabBarFixture(
      animator: animator.animate, reducedMotion: false, attached: false,
      initialLayoutReady: false, initialFrame: .zero, automaticLayout: false,
      fittingHeight: 49, schedulePreparation: preparation.schedule
    )
    fixture.setAttached(true)
    #expect(animator.animations.isEmpty)
    #expect(preparation.pending.isEmpty)
    #expect(fixture.host.slidingView.isHidden)
    #expect(fixture.presentation["interactive"] as? Bool == false)

    fixture.host.frame.size = CGSize(width: 393, height: 49)
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    #expect(preparation.pending.isEmpty)
    fixture.environment.fittingHeight = 83
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    var args = fixture.snapshot(selected: "settings")
    args["brightness"] = "dark"
    #expect(fixture.update(args) == nil)
    #expect(preparation.pending.isEmpty)
    #expect(fixture.host.slidingView.isHidden)

    fixture.host.frame.size.height = 83
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    #expect(preparation.pending.count == 1)
    #expect(animator.animations.isEmpty)
    #expect(fixture.host.slidingView.transform.ty == 83)
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(fixture.host.accessibilityElementsHidden)
    preparation.runNext()
    let entrance = try #require(animator.animations.last)
    #expect(entrance.start.ty == 83)
    #expect(entrance.duration == 0.180)
    #expect(fixture.bar.selectedItem?.accessibilityIdentifier == "settings")
    #expect(fixture.host.overrideUserInterfaceStyle == .dark)
    #expect(fixture.bar.bounds.size == fixture.host.bounds.size)
    entrance.finish()
    #expect(fixture.presentation["interactive"] as? Bool == true)
  }

  @Test("Preparation revalidates changed geometry and uses the newest queued content")
  func preparationInvalidationAndLatestContent() throws {
    let animator = NativeTabBarTestAnimator()
    let preparation = NativeTabBarTestPreparationScheduler()
    let fixture = NativeTabBarFixture(
      animator: animator.animate, reducedMotion: false, fittingHeight: 83,
      schedulePreparation: preparation.schedule
    )
    #expect(preparation.pending.count == 1)
    var args = fixture.snapshot(selected: "settings")
    args["brightness"] = "dark"
    #expect(fixture.update(args) == nil)
    #expect(preparation.pending.count == 2)
    preparation.runNext()
    #expect(animator.animations.isEmpty)
    fixture.host.frame.size.height = 49
    preparation.runNext()
    #expect(animator.animations.isEmpty)
    #expect(fixture.host.slidingView.isHidden)
    fixture.host.frame.size.height = 83
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    preparation.runNext()
    #expect(animator.animations.count == 1)
    #expect(fixture.bar.selectedItem?.accessibilityIdentifier == "settings")
    #expect(fixture.host.overrideUserInterfaceStyle == .dark)
  }

  @Test("Coverage changes input and accessibility without moving the visible material")
  func inputOnlyCoverageGate() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    animator.animations.last?.finish()
    let selected = try #require(fixture.bar.selectedItem)
    let originalTransform = fixture.host.slidingView.transform
    let initialRevision = try #require(fixture.presentation["revision"] as? Int64)
    var args = fixture.snapshot()
    args["inputEnabled"] = false
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    let coveredRevision = try #require(fixture.presentation["revision"] as? Int64)
    #expect(coveredRevision > initialRevision)
    #expect(animator.animations.count == 1)
    #expect(fixture.host.slidingView.transform == originalTransform)
    #expect(!fixture.host.slidingView.isHidden)
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(!fixture.bar.isUserInteractionEnabled)
    #expect(fixture.host.accessibilityElementsHidden)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    #expect(fixture.selectionEvents.isEmpty)
    args["inputEnabled"] = true
    args["visibilityEpoch"] = 2
    #expect(fixture.update(args) == nil)
    #expect(animator.animations.count == 1)
    #expect(fixture.presentation["interactive"] as? Bool == true)
    #expect(try #require(fixture.presentation["revision"] as? Int64) > coveredRevision)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    let event = try #require(fixture.selectionEvents.last?.arguments as? [String: Any])
    #expect(event["visibilityEpoch"] as? Int64 == 2)
    #expect(event["revision"] as? Int64 == fixture.presentation["revision"] as? Int64)
  }

  @Test("Visible native material waits for route input even after its entrance settles")
  func firstRevealWhileCovered() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(
      animator: animator.animate, reducedMotion: false, initialInputEnabled: false
    )
    #expect(animator.animations.count == 1)
    let selected = try #require(fixture.bar.selectedItem)
    let touchPoint = CGPoint(x: fixture.host.bounds.midX, y: fixture.host.bounds.midY)
    #expect(fixture.presentation["phase"] as? String == "entering")
    #expect(fixture.host.hitTest(touchPoint, with: nil) == nil)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    #expect(fixture.selectionEvents.isEmpty)
    animator.animations.last?.finish()
    #expect(fixture.presentation["phase"] as? String == "visible")
    #expect(!fixture.host.slidingView.isHidden)
    #expect(fixture.host.slidingView.transform == .identity)
    #expect(fixture.presentation["interactive"] as? Bool == false)
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(!fixture.bar.isUserInteractionEnabled)
    #expect(fixture.host.accessibilityElementsHidden)
    #expect(fixture.host.hitTest(touchPoint, with: nil) == nil)
    #expect(fixture.bar.hitTest(touchPoint, with: nil) == nil)
    // A native accessibility action reaches the same delegate as a committed
    // pointer selection; neither may navigate while the route is unsettled.
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    #expect(fixture.selectionEvents.isEmpty)
    var args = fixture.snapshot()
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    #expect(fixture.presentation["phase"] as? String == "visible")
    #expect(fixture.presentation["interactive"] as? Bool == true)
    #expect(fixture.host.isUserInteractionEnabled)
    #expect(fixture.bar.isUserInteractionEnabled)
    #expect(!fixture.host.accessibilityElementsHidden)
    #expect(animator.animations.count == 1)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    #expect(fixture.selectionEvents.count == 1)
    let event = try #require(fixture.selectionEvents.first?.arguments as? [String: Any])
    #expect(event["visibilityEpoch"] as? Int64 == 1)
    #expect(event["revision"] as? Int64 == fixture.presentation["revision"] as? Int64)
  }

  @Test("Cancelling a visual return hides the bar before route input was ever enabled")
  func cancelledReturnRemainsNoninteractive() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(
      animator: animator.animate, reducedMotion: false, initiallyHidden: true,
      initialInputEnabled: false
    )
    var args = fixture.snapshot()
    args["inputEnabled"] = false
    args["showRequestId"] = 1
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    let entrance = try #require(animator.animations.last)
    let selected = try #require(fixture.bar.selectedItem)
    entrance.progress(to: 0.6)
    #expect(!fixture.host.slidingView.isHidden)
    #expect(fixture.presentation["interactive"] as? Bool == false)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    #expect(fixture.selectionEvents.isEmpty)
    args["hidden"] = true
    args["visibilityEpoch"] = 2
    #expect(fixture.update(args) == nil)
    #expect(entrance.cancelled)
    #expect(fixture.presentation["phase"] as? String == "exiting")
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(!fixture.bar.isUserInteractionEnabled)
    #expect(fixture.host.accessibilityElementsHidden)
    let exit = try #require(animator.animations.last)
    exit.finish()
    entrance.completeEvenIfCancelled()
    #expect(fixture.presentation["phase"] as? String == "hidden")
    #expect(fixture.presentation["settledHidden"] as? Bool == true)
    #expect(fixture.presentation["interactive"] as? Bool == false)
    #expect(fixture.host.slidingView.isHidden)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    #expect(fixture.selectionEvents.isEmpty)
  }

  @Test("Initial pending preparation survives a hierarchy move but does not replay a settled entrance")
  func firstRevealVersusReattachment() throws {
    let animator = NativeTabBarTestAnimator()
    let preparation = NativeTabBarTestPreparationScheduler()
    let fixture = NativeTabBarFixture(
      animator: animator.animate, reducedMotion: false,
      schedulePreparation: preparation.schedule
    )
    fixture.setAttached(false)
    preparation.runNext()
    #expect(animator.animations.isEmpty)
    fixture.setAttached(true)
    preparation.runNext()
    #expect(animator.animations.count == 1)
    let entrance = try #require(animator.animations.last)
    entrance.finish()
    let revision = try #require(fixture.presentation["revision"] as? Int64)
    fixture.setAttached(false)
    #expect(fixture.presentation["interactive"] as? Bool == false)
    fixture.setAttached(true)
    #expect(animator.animations.count == 1)
    #expect(preparation.pending.isEmpty)
    #expect(fixture.host.slidingView.transform == .identity)
    #expect(fixture.presentation["interactive"] as? Bool == true)
    #expect(try #require(fixture.presentation["revision"] as? Int64) > revision)
  }

  @Test("Hide and disposal invalidate a queued first reveal before it can show")
  func cancelledPreparationCannotReveal() {
    let animator = NativeTabBarTestAnimator()
    let preparation = NativeTabBarTestPreparationScheduler()
    let fixture = NativeTabBarFixture(
      animator: animator.animate, reducedMotion: false,
      schedulePreparation: preparation.schedule
    )
    var args = fixture.snapshot()
    args["hidden"] = true
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    preparation.runNext()
    #expect(animator.animations.isEmpty)
    #expect(fixture.host.slidingView.isHidden)
    args["hidden"] = false
    args["visibilityEpoch"] = 2
    #expect(fixture.update(args) == nil)
    #expect(preparation.pending.count == 1)
    fixture.platformView = nil
    preparation.runNext()
    #expect(animator.animations.isEmpty)
    #expect(fixture.host.slidingView.isHidden)
    #expect(!fixture.messenger.hasHandler)
  }

  @Test("The root receives actual settled-hidden acknowledgement only after the exit completes")
  func settledHiddenAcknowledgement() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    animator.animations.last?.finish()
    #expect(fixture.presentation["phase"] as? String == "visible")
    #expect(fixture.presentation["settledHidden"] as? Bool == false)
    var args = fixture.snapshot()
    args["hidden"] = true
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    #expect(fixture.presentation["phase"] as? String == "exiting")
    #expect(fixture.presentation["settledHidden"] as? Bool == false)
    let exit = try #require(animator.animations.last)
    #expect(exit.duration == 0.140)
    exit.finish()
    #expect(fixture.presentation["phase"] as? String == "hidden")
    #expect(fixture.presentation["settledHidden"] as? Bool == true)
    let revision = try #require(fixture.presentation["revision"] as? Int64)
    // A coalesced/repeated hidden request still needs a fresh acknowledgement.
    #expect(fixture.update(args) == nil)
    #expect(try #require(fixture.presentation["revision"] as? Int64) > revision)
    args["visibilityEpoch"] = 2
    #expect(fixture.update(args) == nil)
    #expect(fixture.presentation["visibilityEpoch"] as? Int64 == 2)
    #expect(fixture.presentation["settledHidden"] as? Bool == true)
  }

  @Test("Each explicit show after Offstage waits for valid layout and plays its prepared entrance")
  func repeatedExplicitShowsAfterOffstage() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    animator.animations.last?.finish()
    for request in 1...3 {
      var args = fixture.snapshot()
      args["showRequestId"] = request - 1
      args["hidden"] = true
      args["visibilityEpoch"] = request * 2 - 1
      #expect(fixture.update(args) == nil)
      animator.animations.last?.finish()
      #expect(fixture.presentation["settledHidden"] as? Bool == true)
      fixture.setAttached(false)
      args["showRequestId"] = request
      args["hidden"] = false
      args["layoutReady"] = false
      args["visibilityEpoch"] = request * 2
      #expect(fixture.update(args) == nil)
      let previousCount = animator.animations.count
      fixture.setAttached(true)
      #expect(animator.animations.count == previousCount)
      #expect(fixture.host.slidingView.isHidden)
      #expect(fixture.presentation["settledHidden"] as? Bool == false)
      args["layoutReady"] = true
      #expect(fixture.update(args) == nil)
      let entrance = try #require(animator.animations.last)
      #expect(animator.animations.count == previousCount + 1)
      #expect(entrance.duration == 0.180)
      #expect(entrance.start.ty > 0)
      #expect(fixture.presentation["phase"] as? String == "entering")
      #expect(fixture.presentation["interactive"] as? Bool == false)
      entrance.finish()
      #expect(fixture.presentation["phase"] as? String == "visible")
      #expect(fixture.presentation["interactive"] as? Bool == true)
    }
  }

  @Test("Coalesced show identities preserve an onscreen bar but survive a detached hierarchy")
  func coalescedShowIdentity() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    animator.animations.last?.finish()
    var args = fixture.snapshot()
    args["showRequestId"] = 1
    args["visibilityEpoch"] = 2
    #expect(fixture.update(args) == nil)
    #expect(animator.animations.count == 1)
    #expect(fixture.host.slidingView.transform == .identity)
    fixture.setAttached(false)
    fixture.setAttached(true)
    #expect(animator.animations.count == 1)
    #expect(fixture.presentation["interactive"] as? Bool == true)
    fixture.setAttached(false)
    args["showRequestId"] = 2
    args["visibilityEpoch"] = 4
    #expect(fixture.update(args) == nil)
    fixture.setAttached(true)
    #expect(animator.animations.count == 2)
    #expect(fixture.presentation["phase"] as? String == "entering")
    #expect(fixture.presentation["interactive"] as? Bool == false)
    animator.animations.last?.finish()
    #expect(fixture.presentation["interactive"] as? Bool == true)
  }

  @Test("Immediate security hide cancels exit, entrance and queued preparation without late reveals")
  func immediateHideCancelsPresentationWork() throws {
    let animator = NativeTabBarTestAnimator()
    let fixture = NativeTabBarFixture(animator: animator.animate, reducedMotion: false)
    animator.animations.last?.finish()
    var args = fixture.snapshot()
    args["hidden"] = true
    args["visibilityEpoch"] = 1
    #expect(fixture.update(args) == nil)
    let exit = try #require(animator.animations.last)
    exit.progress(to: 0.4)
    args["hideImmediately"] = true
    args["visibilityEpoch"] = 2
    #expect(fixture.update(args) == nil)
    #expect(exit.cancelled)
    #expect(fixture.host.slidingView.isHidden)
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(fixture.host.accessibilityElementsHidden)
    #expect(fixture.presentation["settledHidden"] as? Bool == true)
    let hiddenRevision = fixture.presentation["revision"] as? Int64
    exit.completeEvenIfCancelled()
    #expect(fixture.presentation["revision"] as? Int64 == hiddenRevision)
    #expect(fixture.presentation["phase"] as? String == "hidden")

    args["hidden"] = false
    args["hideImmediately"] = false
    args["showRequestId"] = 1
    args["visibilityEpoch"] = 3
    #expect(fixture.update(args) == nil)
    let entrance = try #require(animator.animations.last)
    entrance.progress(to: 0.3)
    args["hidden"] = true
    args["hideImmediately"] = true
    args["visibilityEpoch"] = 4
    #expect(fixture.update(args) == nil)
    #expect(entrance.cancelled)
    entrance.completeEvenIfCancelled()
    #expect(fixture.host.slidingView.isHidden)
    #expect(fixture.presentation["settledHidden"] as? Bool == true)

    let preparation = NativeTabBarTestPreparationScheduler()
    let pendingAnimator = NativeTabBarTestAnimator()
    let pending = NativeTabBarFixture(
      animator: pendingAnimator.animate, reducedMotion: false,
      schedulePreparation: preparation.schedule
    )
    var hidden = pending.snapshot()
    hidden["hidden"] = true
    hidden["hideImmediately"] = true
    hidden["visibilityEpoch"] = 1
    #expect(pending.update(hidden) == nil)
    preparation.runNext()
    #expect(pendingAnimator.animations.isEmpty)
    #expect(pending.host.slidingView.isHidden)
    #expect(pending.presentation["settledHidden"] as? Bool == true)
  }

  @Test("Show request identities and immediate-hide arguments validate atomically")
  func rootPresentationValidation() {
    let fixture = NativeTabBarFixture()
    var args = fixture.snapshot()
    args["showRequestId"] = 3
    args["visibilityEpoch"] = 3
    #expect(fixture.update(args) == nil)
    for invalid: Any in [-1, 1.5, true, "4", 2] {
      args["showRequestId"] = invalid
      #expect(fixture.update(args) is FlutterError)
      #expect(fixture.presentation["phase"] as? String == "visible")
      #expect(fixture.presentation["interactive"] as? Bool == true)
    }
    args["showRequestId"] = 3
    args["hideImmediately"] = true
    #expect(fixture.update(args) is FlutterError)
    #expect(fixture.presentation["phase"] as? String == "visible")
    args["hidden"] = true
    args["hideImmediately"] = "yes"
    #expect(fixture.update(args) is FlutterError)
    #expect(fixture.presentation["phase"] as? String == "visible")
  }

  @Test("Offstage measurements cannot replace the last valid attached height")
  func attachedHeightSurvivesOffstage() async throws {
    let fixture = NativeTabBarFixture(fittingHeight: 83)
    await drainMainQueue()
    #expect(fixture.messenger.call("getHeight") as? Double == 83)
    fixture.messenger.outgoing.removeAll()
    fixture.setAttached(false)
    fixture.environment.fittingHeight = 49
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    #expect(fixture.host.preferredHeight == 49)
    #expect(fixture.messenger.call("getHeight") as? Double == 83)
    await drainMainQueue()
    #expect(fixture.messenger.outgoing.filter { $0.method == "layout" }.isEmpty)
    fixture.environment.fittingHeight = 83
    fixture.setAttached(true)
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    await drainMainQueue()
    let heights = fixture.messenger.outgoing.filter { $0.method == "layout" }.compactMap {
      ($0.arguments as? [String: Double])?["height"]
    }
    #expect(!heights.contains(49))
    #expect(fixture.messenger.call("getHeight") as? Double == 83)
  }

  @Test("All four tab images load from the real app bundle as cached 25pt templates")
  func mainBundleIconAssets() throws {
    let names = ["home", "swap_arrows", "history", "cog"]
    let catalog = NativeTabBarIconCatalog()
    #expect(catalog.availableNames == names)
    #expect(catalog.capabilities(supported: true)["iconNames"] as? [String] == names)
    #expect(catalog.capabilities(supported: true)["supported"] as? Bool == true)
    #expect(catalog.capabilities(supported: false)["supported"] as? Bool == false)
    for name in names {
      #expect(UIImage(named: "VizorTab_\(name)", in: .main, compatibleWith: nil) != nil)
      let image = try #require(catalog.image(named: name))
      #expect(image.size == CGSize(width: 25, height: 25))
      #expect(image.renderingMode == .alwaysTemplate)
      #expect(catalog.image(named: name) === image)
    }
    #expect(catalog.image(named: "VizorTab_home") == nil)
    #expect(catalog.image(named: "../home") == nil)
  }

  @Test("Capability preflight excludes missing catalog assets and updates remain atomic")
  func missingAssetCapabilityAndAtomicity() throws {
    var loads: [String] = []
    let catalog = NativeTabBarIconCatalog { asset in
      loads.append(asset)
      guard asset != "VizorTab_swap_arrows" else { return nil }
      return UIImage(named: asset, in: .main, compatibleWith: nil)
    }
    let capabilities = catalog.capabilities(supported: true)
    #expect(capabilities["iconNames"] as? [String] == ["home", "history", "cog"])
    #expect(loads.contains("VizorTab_swap_arrows"))
    let fixture = NativeTabBarFixture(icons: catalog)
    let originalItem = try #require(fixture.bar.items?.first)
    let originalSelection = fixture.bar.selectedItem
    let originalRevision = fixture.presentation["revision"] as? Int64
    var args = fixture.snapshot(ids: ["home", "swap", "settings"], selected: "swap")
    var items = try #require(args["items"] as? [[String: Any]])
    items[0]["label"] = "Must not partially apply"
    args["items"] = items
    args["hidden"] = true
    #expect(fixture.update(args) is FlutterError)
    #expect(fixture.bar.items?.first === originalItem)
    #expect(originalItem.title == "home")
    #expect(fixture.bar.selectedItem === originalSelection)
    #expect(fixture.presentation["revision"] as? Int64 == originalRevision)
    #expect(fixture.presentation["interactive"] as? Bool == true)
    #expect(loads.filter { $0 == "VizorTab_home" }.count == 1)
    #expect(loads.filter { $0 == "VizorTab_history" }.count == 1)
    #expect(loads.filter { $0 == "VizorTab_cog" }.count == 1)
  }

  @Test("Missing, malformed and unknown icon names never erase a displayed icon")
  func invalidIconNames() throws {
    let fixture = NativeTabBarFixture()
    let item = try #require(fixture.bar.items?.first)
    let image = try #require(item.image)
    for invalid: Any? in [nil, "", "unknown", 7] {
      var args = fixture.snapshot()
      var items = try #require(args["items"] as? [[String: Any]])
      items[0]["iconName"] = invalid
      args["items"] = items
      #expect(fixture.update(args) is FlutterError)
      #expect(fixture.bar.items?.first === item)
      #expect(item.image === image)
    }
  }

  @Test("Press feedback starts on touch-down, including the selected tab, never on selection")
  func pressFeedbackOnTouchDown() throws {
    let feedback = NativeTabBarFeedbackSpy()
    let fixture = NativeTabBarFixture(pressFeedback: feedback)
    let observer = try #require(fixture.pressObserver)
    let first = NativeTabBarTestTouch(view: try #require(fixture.bar.hitTest(
      CGPoint(x: fixture.bar.bounds.width / 6, y: 20), with: nil)))
    let event = UIEvent()
    observer.touchesBegan([first], with: event)
    #expect(feedback.impacts == 1)
    #expect(fixture.selectionEvents.isEmpty)
    #expect(observer.state == .possible)
    observer.touchesMoved([first], with: event)
    observer.touchesEnded([first], with: event)
    fixture.platformView?.tabBar(fixture.bar, didSelect: try #require(fixture.bar.selectedItem))
    #expect(feedback.impacts == 1)
    observer.touchesBegan([first], with: event)
    #expect(feedback.impacts == 2)
    observer.touchesEnded([first], with: event)
    let last = NativeTabBarTestTouch(view: try #require(fixture.bar.hitTest(
      CGPoint(x: fixture.bar.bounds.width * 5 / 6, y: 20), with: nil)))
    observer.touchesBegan([last], with: event)
    #expect(feedback.impacts == 3)
    observer.touchesCancelled([last], with: event)
    #expect(feedback.impacts == 3)
  }

  @Test("Only direct item contacts emit press feedback, not background, safe area or foreign views")
  func pressFeedbackContactScope() throws {
    let feedback = NativeTabBarFeedbackSpy()
    let fixture = NativeTabBarFixture(pressFeedback: feedback)
    let observer = try #require(fixture.pressObserver)
    let event = UIEvent()
    let item = try #require(fixture.bar.hitTest(
      CGPoint(x: fixture.bar.bounds.width / 6, y: 20), with: nil))
    for touch in [
      NativeTabBarTestTouch(view: fixture.bar),
      NativeTabBarTestTouch(view: fixture.host),
      NativeTabBarTestTouch(view: UIControl()),
      NativeTabBarTestTouch(view: item, type: .indirectPointer),
      NativeTabBarTestTouch(view: item, type: .pencil),
    ] {
      observer.touchesBegan([touch], with: event)
      observer.touchesEnded([touch], with: event)
    }
    #expect(feedback.impacts == 0)
    observer.touchesBegan([NativeTabBarTestTouch(view: item)], with: event)
    #expect(feedback.impacts == 1)
  }

  @Test("Visible but disabled, hidden and unprepared tabs cannot emit press feedback")
  func pressFeedbackRespectsInputGate() throws {
    let feedback = NativeTabBarFeedbackSpy()
    let fixture = NativeTabBarFixture(pressFeedback: feedback)
    let observer = try #require(fixture.pressObserver)
    let touch = NativeTabBarTestTouch(view: try #require(fixture.bar.hitTest(
      CGPoint(x: fixture.bar.bounds.width / 6, y: 20), with: nil)))
    let event = UIEvent()
    for field in ["inputEnabled", "hidden", "layoutReady"] {
      var args = fixture.snapshot()
      args[field] = field == "hidden"
      #expect(fixture.update(args) == nil)
      #expect(fixture.presentation["interactive"] as? Bool == false)
      #expect(!observer.isEnabled)
      observer.touchesBegan([touch], with: event)
      #expect(feedback.impacts == 0)
      #expect(fixture.update(fixture.snapshot()) == nil)
    }
    observer.touchesBegan([touch], with: event)
    #expect(feedback.impacts == 1)
    #expect(feedback.preparations > 0)
  }

  @Test("A multi-finger drag or cancellation emits at most one pulse and cannot arbitrate UIKit gestures")
  func pressFeedbackSequenceAndGestureIsolation() throws {
    let feedback = NativeTabBarFeedbackSpy()
    let fixture = NativeTabBarFixture(pressFeedback: feedback)
    let observer = try #require(fixture.pressObserver)
    let view = try #require(fixture.bar.hitTest(
      CGPoint(x: fixture.bar.bounds.width / 6, y: 20), with: nil))
    let first = NativeTabBarTestTouch(view: view)
    let second = NativeTabBarTestTouch(view: view)
    let event = UIEvent()
    observer.touchesBegan([first], with: event)
    observer.touchesBegan([second], with: event)
    observer.touchesEnded([first], with: event)
    observer.touchesMoved([second], with: event)
    #expect(observer.state == .possible)
    #expect(feedback.impacts == 1)
    observer.touchesCancelled([second], with: event)
    #expect(feedback.impacts == 1)
    // UIKit may already have reset a failed observer for the next sequence.
    #expect(observer.state == .possible || observer.state == .failed)
    #expect(!observer.cancelsTouchesInView)
    #expect(!observer.delaysTouchesBegan)
    #expect(!observer.delaysTouchesEnded)
    let systemGesture = UIPanGestureRecognizer()
    #expect(!observer.canPrevent(systemGesture))
    #expect(!observer.canBePrevented(by: systemGesture))
    observer.touchesBegan([first], with: event)
    #expect(feedback.impacts == 2)
  }

  @Test("Disposal removes the press observer and invalidates its callbacks")
  func pressFeedbackDisposal() throws {
    let feedback = NativeTabBarFeedbackSpy()
    let fixture = NativeTabBarFixture(pressFeedback: feedback)
    let observer = try #require(fixture.pressObserver)
    let touch = NativeTabBarTestTouch(view: try #require(fixture.bar.hitTest(
      CGPoint(x: fixture.bar.bounds.width / 6, y: 20), with: nil)))
    fixture.platformView = nil
    #expect(!(fixture.bar.gestureRecognizers ?? []).contains(observer))
    observer.touchesBegan([touch], with: UIEvent())
    #expect(feedback.impacts == 0)
  }

  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}

@MainActor
private final class NativeTabBarFixture {
  let messenger = NativeTabBarMessenger()
  let environment: NativeTabBarTestEnvironment
  let notifications = NotificationCenter()
  var platformView: NativeTabBarPlatformView?
  let host: NativeTabBarHostView
  var bar: UITabBar { host.tabBar }
  var presentation: [String: Any] {
    messenger.call("getPresentation") as? [String: Any] ?? [:]
  }
  var selectionEvents: [FlutterMethodCall] { messenger.outgoing.filter { $0.method == "select" } }
  var pressObserver: NativeTabBarPressObserver? {
    bar.gestureRecognizers?.compactMap { $0 as? NativeTabBarPressObserver }.first
  }

  init(
    animator: NativeTabBarAnimator? = nil, reducedMotion: Bool = true,
    icons: NativeTabBarIconCatalog = .shared,
    attached: Bool = true, initiallyHidden: Bool = false,
    initialLayoutReady: Bool = true, initialInputEnabled: Bool = true,
    initialFrame: CGRect = CGRect(x: 0, y: 0, width: 393, height: 100),
    automaticLayout: Bool = true, fittingHeight: CGFloat? = nil,
    pressFeedback: NativeTabBarPressFeedback? = nil,
    schedulePreparation: @escaping (@escaping () -> Void) -> Void = { $0() }
  ) {
    let environment = NativeTabBarTestEnvironment()
    environment.reducedMotion = reducedMotion
    environment.attached = attached
    environment.fittingHeight = fittingHeight
    self.environment = environment
    var args = Self.snapshot(ids: ["home", "activity", "settings"], selected: "home")
    args["hidden"] = initiallyHidden
    args["layoutReady"] = initialLayoutReady
    args["inputEnabled"] = initialInputEnabled
    let platformView = NativeTabBarPlatformView(
      frame: initialFrame,
      viewId: 1, args: args, messenger: messenger, icons: icons, animator: animator,
      reduceMotion: { environment.reducedMotion }, attachmentProvider: { environment.attached },
      notificationCenter: notifications,
      fittingHeight: fittingHeight == nil ? nil : { _, _ in environment.fittingHeight! },
      pressFeedback: pressFeedback,
      schedulePreparation: schedulePreparation
    )
    self.platformView = platformView
    host = platformView.view() as! NativeTabBarHostView
    if automaticLayout {
      host.frame.size.height = host.preferredHeight
      host.setNeedsLayout()
      host.layoutIfNeeded()
    }
    messenger.outgoing.removeAll()
  }

  func setAttached(_ attached: Bool) {
    environment.attached = attached
    host.didMoveToWindow()
  }

  func snapshot(ids: [String] = ["home", "activity", "settings"], selected: String = "home")
    -> [String: Any]
  {
    Self.snapshot(ids: ids, selected: selected)
  }

  func update(_ args: [String: Any]) -> Any? {
    messenger.call("update", arguments: args)
  }

  private static func snapshot(ids: [String], selected: String) -> [String: Any] {
    [
      "items": ids.map {
        let iconName = switch $0 {
        case "swap": "swap_arrows"
        case "activity": "history"
        case "settings": "cog"
        default: "home"
        }
        return ["id": $0, "label": $0, "iconName": iconName]
      },
      "selectedId": selected,
      "brightness": "light",
      "direction": "ltr",
      "visibilityEpoch": 0,
      "showRequestId": 0,
      "hideImmediately": false,
      "inputEnabled": true,
      "layoutReady": true,
    ]
  }
}

private final class NativeTabBarFeedbackSpy: NativeTabBarPressFeedback {
  var preparations = 0
  var impacts = 0
  func prepare() { preparations += 1 }
  func impactOccurred() { impacts += 1 }
}

private final class NativeTabBarTestTouch: UITouch {
  private let target: UIView
  private let touchType: UITouch.TouchType
  init(view: UIView, type: UITouch.TouchType = .direct) {
    target = view
    touchType = type
    super.init()
  }
  override var view: UIView? { target }
  override var type: UITouch.TouchType { touchType }
}

private final class NativeTabBarTestEnvironment {
  var reducedMotion = true
  var attached = true
  var fittingHeight: CGFloat?
}

private final class NativeTabBarTestPreparationScheduler {
  var pending: [() -> Void] = []
  func schedule(_ completion: @escaping () -> Void) { pending.append(completion) }
  func runNext() {
    guard !pending.isEmpty else { return }
    pending.removeFirst()()
  }
}

private final class NativeTabBarTestAnimator {
  var animations: [NativeTabBarTestAnimation] = []

  func animate(
    view: UIView, target: CGAffineTransform, duration: TimeInterval,
    timing: UICubicTimingParameters, completion: @escaping () -> Void
  ) -> NativeTabBarAnimation {
    let animation = NativeTabBarTestAnimation(
      view: view, target: target, duration: duration, timing: timing, completion: completion
    )
    animations.append(animation)
    return animation
  }
}

private final class NativeTabBarTestAnimation: NativeTabBarAnimation {
  private weak var view: UIView?
  let start: CGAffineTransform
  let target: CGAffineTransform
  let duration: TimeInterval
  let timing: UICubicTimingParameters
  private let completion: () -> Void
  private(set) var cancelled = false

  init(
    view: UIView, target: CGAffineTransform, duration: TimeInterval,
    timing: UICubicTimingParameters, completion: @escaping () -> Void
  ) {
    self.view = view
    start = view.transform
    self.target = target
    self.duration = duration
    self.timing = timing
    self.completion = completion
  }

  func progress(to fraction: CGFloat) {
    view?.transform = CGAffineTransform(
      translationX: start.tx + (target.tx - start.tx) * fraction,
      y: start.ty + (target.ty - start.ty) * fraction
    )
  }

  func finish() {
    guard !cancelled else { return }
    view?.transform = target
    completion()
  }

  func completeEvenIfCancelled() { completion() }
  func cancel() { cancelled = true }
}

private final class NativeTabBarMessenger: NSObject, FlutterBinaryMessenger {
  private let codec = FlutterStandardMethodCodec.sharedInstance()
  private var handler: FlutterBinaryMessageHandler?
  var outgoing: [FlutterMethodCall] = []
  var hasHandler: Bool { handler != nil }

  func call(_ method: String, arguments: Any? = nil) -> Any? {
    var result: Any?
    handler?(codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))) { reply in
      if let reply { result = self.codec.decodeEnvelope(reply) }
    }
    return result
  }

  func send(onChannel channel: String, message: Data?) {
    if let message { outgoing.append(codec.decodeMethodCall(message)) }
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    self.handler = handler
    return 1
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    handler = nil
  }
}
