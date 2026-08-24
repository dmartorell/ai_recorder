import SwiftUI
import SwiftData
import AVFAudio

@main
struct AIRecorderApp: App {
    let modelContainer: ModelContainer
    @State private var coordinator: CaptureCoordinator
    @State private var settings = SettingsModel()
    let recoveryService: RecoveryService

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)
            let container = try ModelContainer(for: AudioItem.self, Marker.self, CaptureEventRecord.self, configurations: configuration)
            modelContainer = container
            let files = try AudioFileStore.applicationStore()
            if isUITesting, ProcessInfo.processInfo.arguments.contains("-local-audio-fixture") {
                let item = AudioItem(fileName: "ui-test-source.m4a")
                item.localState = .available
                item.durationMilliseconds = 2_500
                container.mainContext.insert(item)
                try Data("ui-test-audio".utf8).write(to: files.url(for: item.id))
                try container.mainContext.save()
            }
            let recorder: any CaptureRecorder = isUITesting ? UITestCaptureRecorder() : FragmentedM4ARecorder()
            let inspector: any AudioInspector = isUITesting ? UITestAudioInspector() : OriginalAudioInspector()
            let storageMonitor: (any StorageMonitoring)? = isUITesting ? UITestStorageMonitor() : nil
            _coordinator = State(initialValue: CaptureCoordinator(repository: AudioRepository(context: container.mainContext, files: files), recorder: recorder, inspector: inspector, storageMonitor: storageMonitor, permissionProvider: { isUITesting || AVAudioApplication.shared.recordPermission == .granted }))
            recoveryService = RecoveryService(context: container.mainContext, files: files, inspector: inspector)
        } catch {
            fatalError("Unable to initialize local storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator, recoveryService: recoveryService, settings: settings)
                .environment(\.locale, settings.locale)
        }
        .modelContainer(modelContainer)
    }
}
