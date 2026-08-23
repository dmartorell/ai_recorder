import Foundation
import XCTest
@testable import AIRecorder

final class OriginalAudioInspectorTests: XCTestCase {
    func testMissingOriginalAudioIsRejected() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        await XCTAssertThrowsErrorAsync(try await OriginalAudioInspector().inspect(url)) { error in
            XCTAssertEqual(error as? OriginalAudioInspectionError, .missing)
        }
    }

    func testEmptyOriginalAudioIsRejectedWithoutBeingModified() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await XCTAssertThrowsErrorAsync(try await OriginalAudioInspector().inspect(url)) { error in
            XCTAssertEqual(error as? OriginalAudioInspectionError, .empty)
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        XCTAssertEqual(size, 0)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
