import UIKit

final class BackgroundURLSessionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == "com.airecorder.cloud-backup" else {
            completionHandler()
            return
        }
        Task { @MainActor in
            BackgroundURLSessionPartUploader.shared.handleEventsForBackgroundURLSession(completionHandler: completionHandler)
        }
    }
}
