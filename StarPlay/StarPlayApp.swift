import SwiftUI
import AVFoundation

// MARK: - Orientation control
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .moviePlayback,
            options: [.allowBluetooth, .allowAirPlay, .mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
        return true
    }
}

// MARK: - App Entry
@main
struct StarPlayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var prefs        = AppPreferences()

    var body: some Scene {
        WindowGroup {
            AppNavigator()
                .environmentObject(themeManager)
                .environmentObject(prefs)
                .preferredColorScheme(.dark)
        }
    }
}
