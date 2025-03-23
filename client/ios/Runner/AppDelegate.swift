import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Set up plugin registrant callback
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }

    // Register the plugin with the app delegate
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up UNUserNotificationCenter delegate for iOS 10 and above
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    // Ensure everything is correctly initialized
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
