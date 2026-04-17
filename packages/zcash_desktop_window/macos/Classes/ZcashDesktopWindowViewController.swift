import Cocoa
import FlutterMacOS

public final class ZcashDesktopWindowViewController: NSViewController {
  private let _flutterViewController: FlutterViewController

  public var flutterViewController: FlutterViewController {
    _flutterViewController
  }

  public var visualEffectView: NSVisualEffectView {
    view as! NSVisualEffectView
  }

  public init(flutterViewController: FlutterViewController? = nil) {
    _flutterViewController = flutterViewController ?? FlutterViewController()
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override func loadView() {
    let effectView = NSVisualEffectView()
    effectView.autoresizingMask = [.width, .height]
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    if #available(macOS 10.14, *) {
      effectView.material = .fullScreenUI
    }
    view = effectView
  }

  public override func viewDidLoad() {
    super.viewDidLoad()

    addChild(_flutterViewController)
    _flutterViewController.view.frame = view.bounds
    _flutterViewController.view.autoresizingMask = [.width, .height]
    _flutterViewController.backgroundColor = .clear
    view.addSubview(_flutterViewController.view)
  }
}
