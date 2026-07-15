import Foundation
import XCTest
@testable import FundPulse

final class JDFinanceDebugArtifactsTests: XCTestCase {
    func testCleanupRemovesOnlyLegacyJDFinanceDebugArtifacts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-jd-debug-artifacts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for fileName in JDFinanceDebugArtifacts.fileNames {
            try Data("sensitive fixture".utf8).write(to: directory.appending(path: fileName))
        }
        let keepURL = directory.appending(path: "portfolio.json")
        try Data("keep".utf8).write(to: keepURL)

        JDFinanceDebugArtifacts.removePersistedFiles(in: directory)

        for fileName in JDFinanceDebugArtifacts.fileNames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: fileName).path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: keepURL.path))
    }
}
