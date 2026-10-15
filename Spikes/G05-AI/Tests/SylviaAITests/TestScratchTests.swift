import Foundation
import G05TestSupport
import Testing

/// Review R3-05: tests write stored questions, packs, answers and clips only under one per-process root that is removed
/// when the process exits. CI sets `G05_TEST_SCRATCH` and checks after the run that nothing is left there.
@Suite("Test scratch directories")
struct TestScratchTests {
    @Test func everyScratchDirectoryLivesUnderOneRootInTheConfiguredParent() throws {
        let directory = TestPacks.temporaryDirectory()
        let root = TestPacks.scratchRoot.standardizedFileURL.path
        #expect(directory.standardizedFileURL.path.hasPrefix(root + "/"))
        #expect(TestPacks.scratchRoot.deletingLastPathComponent().standardizedFileURL.path
                == TestPacks.scratchParent.standardizedFileURL.path)
        #expect(TestPacks.scratchRoot.lastPathComponent.hasPrefix("g05-tests-\(ProcessInfo.processInfo.processIdentifier)-"))
        if let configured = ProcessInfo.processInfo.environment["G05_TEST_SCRATCH"], !configured.isEmpty {
            #expect(TestPacks.scratchParent.standardizedFileURL.path == URL(fileURLWithPath: configured).standardizedFileURL.path,
                    "the CI's scratch directory is the one used")
        }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }
}
