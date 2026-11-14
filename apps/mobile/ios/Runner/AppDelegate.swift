import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let dmNotifications = DmNotifications()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechFULDmNotifications") {
      dmNotifications.register(registrar.messenger())
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if dmNotifications.owns(notification) {
      DispatchQueue.main.async { completionHandler(self.dmNotifications.presentation(notification)) }
    }
    else { super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    if dmNotifications.owns(response.notification) {
      DispatchQueue.main.async {
        self.dmNotifications.receive(response)
        completionHandler()
      }
    } else { super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler) }
  }
}
