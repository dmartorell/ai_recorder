import SwiftUI
import SwiftData
import AVFAudio

@main
struct AIRecorderApp: App {
    @UIApplicationDelegateAdaptor(BackgroundURLSessionAppDelegate.self) private var backgroundURLSessionAppDelegate
    let modelContainer: ModelContainer
    @State private var coordinator: CaptureCoordinator
    @State private var settings = SettingsModel()
    @State private var cloudIdentity: CloudIdentityCoordinator
    @State private var cloudBackup: CloudBackupCoordinator
    let recoveryService: RecoveryService
    let cloudBackupRecoveryService: CloudBackupRecoveryService

    init() {
        _ = BackgroundURLSessionPartUploader.shared
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
            let cloudConfiguration = isUITesting ? nil : SupabaseConfiguration.load()
            let authentication: any CloudAuthenticating = cloudConfiguration.map(SupabaseCloudAuthentication.init) ?? UnavailableCloudAuthentication()
            let backupClient: any CloudBackupClient = cloudConfiguration?.cloudBackupWorkerURL.map {
                WorkerCloudBackupClient(baseURL: $0, authentication: authentication)
            } ?? UnavailableCloudBackupClient()
            let backupPersistence = SwiftDataCloudBackupPersistence(context: container.mainContext)
            let backupCoordinator = CloudBackupCoordinator(client: backupClient, files: files, persistence: backupPersistence)
            _cloudBackup = State(initialValue: backupCoordinator)
            _cloudIdentity = State(initialValue: CloudIdentityCoordinator(authentication: authentication, backupSession: backupCoordinator))
            cloudBackupRecoveryService = CloudBackupRecoveryService(persistence: backupPersistence, coordinator: backupCoordinator)
        } catch {
            fatalError("Unable to initialize local storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator, recoveryService: recoveryService, cloudBackupRecoveryService: cloudBackupRecoveryService, settings: settings, cloudIdentity: cloudIdentity, cloudBackup: cloudBackup)
                .environment(\.locale, settings.locale)
                .onOpenURL { url in
                    Task {
                        await cloudIdentity.handleMagicLink(url)
                        guard cloudIdentity.state == .authenticated else { return }
                        await cloudBackupRecoveryService.recoverPendingBackups()
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
