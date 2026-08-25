import Foundation

struct CloudBackupPartContext: Codable, Hashable, Sendable {
    let localAudioID: UUID
    let backupID: UUID
    let partNumber: Int
}

struct CloudBackupCompletedPart: Equatable, Sendable {
    let partNumber: Int
    let eTag: String
}

@MainActor
protocol CloudBackupPartUploading: AnyObject {
    func upload(fileURL: URL, to url: URL, sha256: String, context: CloudBackupPartContext) async throws -> String
    func completedParts(for backupID: UUID) -> [CloudBackupCompletedPart]
    func discardCompletedPart(_ partNumber: Int, backupID: UUID)
}

@MainActor
extension CloudBackupPartUploading {
    func completedParts(for backupID: UUID) -> [CloudBackupCompletedPart] { [] }
    func discardCompletedPart(_ partNumber: Int, backupID: UUID) { }
}

@MainActor
final class BackgroundURLSessionPartUploader: NSObject, CloudBackupPartUploading {
    static let shared = BackgroundURLSessionPartUploader()

    private let taskStore: CloudBackupBackgroundTaskStore
    private lazy var session: URLSession = {
        URLSession(
            configuration: .background(withIdentifier: "com.airecorder.cloud-backup"),
            delegate: self,
            delegateQueue: nil
        )
    }()
    private var activeTasks = [CloudBackupPartContext: URLSessionUploadTask]()
    private var continuations = [CloudBackupPartContext: CheckedContinuation<String, Error>]()
    private var didRestoreTasks = false
    private var restorationTask: Task<Void, Never>?
    private var backgroundEventsCompletionHandler: (() -> Void)?

    init(taskStore: CloudBackupBackgroundTaskStore = .applicationStore()) {
        self.taskStore = taskStore
        super.init()
    }

    func upload(fileURL: URL, to url: URL, sha256: String, context: CloudBackupPartContext) async throws -> String {
        await restoreTasksIfNeeded()
        if activeTasks[context] != nil {
            return try await waitForCompletion(context: context)
        }

        let taskDescription = try JSONEncoder().encode(context).base64EncodedString()
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        return try await withCheckedThrowingContinuation { continuation in
            continuations[context] = continuation
            let task = session.uploadTask(with: request, fromFile: fileURL)
            task.taskDescription = taskDescription
            taskStore.save(.init(context: context, filePath: fileURL.path, taskIdentifier: task.taskIdentifier, eTag: nil))
            activeTasks[context] = task
            task.resume()
        }
    }

    func completedParts(for backupID: UUID) -> [CloudBackupCompletedPart] {
        taskStore.records(for: backupID).compactMap { record in
            guard let eTag = record.eTag else { return nil }
            return .init(partNumber: record.context.partNumber, eTag: eTag)
        }
    }

    func discardCompletedPart(_ partNumber: Int, backupID: UUID) {
        taskStore.remove(backupID: backupID, partNumber: partNumber)
    }

    func handleEventsForBackgroundURLSession(completionHandler: @escaping () -> Void) {
        backgroundEventsCompletionHandler = completionHandler
        _ = session
    }

    private func restoreTasksIfNeeded() async {
        guard !didRestoreTasks else { return }
        if let restorationTask {
            await restorationTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            let tasks = await self.session.allTasks
            for task in tasks {
                guard let context = context(for: task), let uploadTask = task as? URLSessionUploadTask else { continue }
                self.activeTasks[context] = uploadTask
                if let record = self.taskStore.record(for: context) {
                    self.taskStore.save(.init(context: context, filePath: record.filePath, taskIdentifier: task.taskIdentifier, eTag: record.eTag))
                }
            }
            self.didRestoreTasks = true
            self.restorationTask = nil
        }
        restorationTask = task
        await task.value
    }

    private func waitForCompletion(context: CloudBackupPartContext) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            continuations[context] = continuation
        }
    }

    private func complete(task: URLSessionTask, error: Error?) {
        guard let context = context(for: task) else { return }
        activeTasks[context] = nil
        if let error {
            continuations.removeValue(forKey: context)?.resume(throwing: error)
            return
        }
        guard let response = task.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let eTag = response.value(forHTTPHeaderField: "ETag"), !eTag.isEmpty
        else {
            continuations.removeValue(forKey: context)?.resume(throwing: CloudBackupError.partUploadFailed)
            return
        }
        guard let record = taskStore.record(for: context) else {
            continuations.removeValue(forKey: context)?.resume(throwing: CloudBackupError.partUploadFailed)
            return
        }
        taskStore.save(.init(context: context, filePath: record.filePath, taskIdentifier: task.taskIdentifier, eTag: eTag))
        continuations.removeValue(forKey: context)?.resume(returning: eTag)
    }

    private func context(for task: URLSessionTask) -> CloudBackupPartContext? {
        if let description = task.taskDescription,
           let data = Data(base64Encoded: description),
           let context = try? JSONDecoder().decode(CloudBackupPartContext.self, from: data) {
            return context
        }
        return taskStore.record(taskIdentifier: task.taskIdentifier)?.context
    }
}

extension BackgroundURLSessionPartUploader: URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        Task { @MainActor [weak self] in self?.complete(task: task, error: error) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            guard let self, let completionHandler = self.backgroundEventsCompletionHandler else { return }
            self.backgroundEventsCompletionHandler = nil
            completionHandler()
        }
    }
}

@MainActor
final class CloudBackupBackgroundTaskStore {
    struct Record: Codable, Equatable {
        let context: CloudBackupPartContext
        let filePath: String
        let taskIdentifier: Int
        let eTag: String?
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    static func applicationStore() -> CloudBackupBackgroundTaskStore {
        .init(defaults: .standard, key: "cloud-backup-background-tasks")
    }

    func record(for context: CloudBackupPartContext) -> Record? {
        records.first { $0.context == context }
    }

    func records(for backupID: UUID) -> [Record] {
        records.filter { $0.context.backupID == backupID }
    }

    func record(taskIdentifier: Int) -> Record? {
        records.first { $0.taskIdentifier == taskIdentifier }
    }

    func save(_ record: Record) {
        var updated = records.filter { $0.context != record.context }
        updated.append(record)
        defaults.set(try? JSONEncoder().encode(updated), forKey: key)
    }

    func remove(backupID: UUID, partNumber: Int) {
        defaults.set(try? JSONEncoder().encode(records.filter { $0.context.backupID != backupID || $0.context.partNumber != partNumber }), forKey: key)
    }

    private var records: [Record] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }
}
