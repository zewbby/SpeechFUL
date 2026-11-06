import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechFULPostSharing") else { return }
    let channel = FlutterMethodChannel(name: "speechful/post-sharing", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "shareText" else { result(FlutterMethodNotImplemented); return }
      guard let text = call.arguments as? String, text.count <= 4096,
            text.hasPrefix("SpeechFUL\nhttps://"),
            let url = URLComponents(string: String(text.dropFirst("SpeechFUL\n".count))),
            url.scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil,
            url.query == nil, url.fragment == nil,
            url.percentEncodedPath.range(of: "^/s/posts/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "SHARE_INVALID", message: "Invalid post share", details: nil)); return
      }
      guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let window = scene.windows.first(where: { $0.isKeyWindow }),
            var presenter = window.rootViewController else {
        result(FlutterError(code: "SHARE_UNAVAILABLE", message: "System sharing unavailable", details: nil)); return
      }
      while let top = presenter.presentedViewController { presenter = top }
      guard !(presenter is UIActivityViewController) else {
        result(FlutterError(code: "SHARE_UNAVAILABLE", message: "System sharing unavailable", details: nil)); return
      }
      let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
      if let popover = sheet.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      sheet.completionWithItemsHandler = { _, _, _, _ in result(nil) }
      presenter.present(sheet, animated: true)
    }
  }
}
