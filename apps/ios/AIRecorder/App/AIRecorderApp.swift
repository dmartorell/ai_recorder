import SwiftUI
import SwiftData
import AVFAudio

@main
struct AIRecorderApp: App {
    let modelContainer: ModelContainer
    @State private var coordinator: CaptureCoordinator
    let recoveryService: RecoveryService

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)
            let container = try ModelContainer(for: AudioItem.self, Marker.self, configurations: configuration)
            modelContainer = container
            let files = try AudioFileStore.applicationStore()
            let recorder: any CaptureRecorder = isUITesting ? UITestCaptureRecorder() : FragmentedM4ARecorder()
            let inspector: any AudioInspector = isUITesting ? UITestAudioInspector() : OriginalAudioInspector()
            _coordinator = State(initialValue: CaptureCoordinator(repository: AudioRepository(context: container.mainContext, files: files), recorder: recorder, inspector: inspector, permissionProvider: { isUITesting || AVAudioApplication.shared.recordPermission == .granted }))
            recoveryService = RecoveryService(context: container.mainContext, files: files, inspector: inspector)
        } catch {
            fatalError("Unable to initialize local storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator, recoveryService: recoveryService)
                .sheet(isPresented: Binding(get: { coordinator.phase == .recording || coordinator.phase == .finalizing }, set: { _ in })) {
                    NavigationStack { RecordingView(coordinator: coordinator) }
                        .presentationDetents([.large])
                }
        }
        .modelContainer(modelContainer)
    }
}
