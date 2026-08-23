import XCTest
@testable import AIRecorder

final class AudioVerifierTests: XCTestCase {
    func testVerifyReturnsMeasuredAudioSummary() async throws {
        let expected = CapturedAudioSummary(duration: 12.5, channelCount: 2)
        let summary = try await AudioVerifier(inspector: FixedInspector(summary: expected)).verify(URL(fileURLWithPath: "/tmp/audio.m4a"))

        XCTAssertEqual(summary, expected)
    }

    func testVerifyPreservesInspectionFailure() async {
        do {
            _ = try await AudioVerifier(inspector: FailingInspector()).verify(URL(fileURLWithPath: "/tmp/audio.m4a"))
            XCTFail("Expected verification to fail")
        } catch {
            XCTAssertEqual(error as? VerificationError, .invalidAudio)
        }
    }

    private struct FixedInspector: AudioInspector {
        let summary: CapturedAudioSummary

        func inspect(_ url: URL) async throws -> CapturedAudioSummary { summary }
    }

    private struct FailingInspector: AudioInspector {
        func inspect(_ url: URL) async throws -> CapturedAudioSummary { throw VerificationError.invalidAudio }
    }

    private enum VerificationError: Error, Equatable {
        case invalidAudio
    }
}
