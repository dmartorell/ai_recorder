import SwiftUI
import SwiftData
import AVFAudio

@main
struct AIRecorderApp: App {
    let modelContainer: ModelContainer
    @State private var coordinator: CaptureCoordinator
    @State private var settings = SettingsModel()
    @State private var cloudIdentity: CloudIdentityCoordinator
    let recoveryService: RecoveryService

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)
            let container = try ModelContainer(for: AudioItem.self, Marker.self, CaptureEventRecord.self, configurations: configuration)
            modelContainer = container
            let files = try AudioFileStore.applicationStore()
            let fixtureCount = ProcessInfo.processInfo.arguments.contains("-local-audio-fixtures")
                ? 3
                : (ProcessInfo.processInfo.arguments.contains("-local-audio-fixture") ? 1 : 0)
            if isUITesting, fixtureCount > 0 {
                for index in 0..<fixtureCount {
                    let item = AudioItem(
                        startedAt: .now.addingTimeInterval(TimeInterval(-index)),
                        fileName: "ui-test-source-\(index).m4a"
                    )
                    item.localState = .available
                    item.durationMilliseconds = 2_500
                    container.mainContext.insert(item)
                    try Data("ui-test-audio".utf8).write(to: files.url(for: item.id))
                }
                try container.mainContext.save()
            }
            let recorder: any CaptureRecorder = isUITesting ? UITestCaptureRecorder() : FragmentedM4ARecorder()
            let inspector: any AudioInspector = isUITesting ? UITestAudioInspector() : OriginalAudioInspector()
            let storageMonitor: (any StorageMonitoring)? = isUITesting ? UITestStorageMonitor() : nil
            _coordinator = State(initialValue: CaptureCoordinator(repository: AudioRepository(context: container.mainContext, files: files), recorder: recorder, inspector: inspector, storageMonitor: storageMonitor, permissionProvider: { isUITesting || AVAudioApplication.shared.recordPermission == .granted }))
            recoveryService = RecoveryService(context: container.mainContext, files: files, inspector: inspector)
            let authentication: any CloudAuthenticating = SupabaseConfiguration.load().map(SupabaseCloudAuthentication.init) ?? UnavailableCloudAuthentication()
            _cloudIdentity = State(initialValue: CloudIdentityCoordinator(authentication: authentication))
        } catch {
            fatalError("Unable to initialize local storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator, recoveryService: recoveryService, settings: settings, cloudIdentity: cloudIdentity)
                .environment(\.locale, settings.locale)
                .onOpenURL { url in
                    Task { await cloudIdentity.handleMagicLink(url) }
                }
        }
        .modelContainer(modelContainer)
    }
}
