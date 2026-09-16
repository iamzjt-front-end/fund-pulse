import CryptoKit
import Foundation
import XCTest
@testable import FundPulse

final class UpdateTrustTests: XCTestCase {
    func testFallbackFeedUsesDigestBelongingToTheSelectedZip() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateFeedProtocol.self]
        let result = try await AppUpdateService(session: URLSession(configuration: config)).check(currentVersion: "1.0")
        let info = try XCTUnwrap(result.updateInfo)
        XCTAssertEqual(info.downloadURL?.lastPathComponent, "fund-pulse-arm64-swift.zip")
        XCTAssertEqual(info.archiveDigest, "sha512:zip-digest")
    }

    // Uses real codesign against isolated bundles; never downloads or installs an update.
    func testAdHocSignatureWithMatchingBundleIDIsNotATrustedUpdate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = try makeApp(in: directory, name: "current", version: "1.0")
        let staged = try makeApp(in: directory, name: "staged", version: "2.0")
        XCTAssertThrowsError(try AppUpdateService().verifyStagedApp(staged, expectedInfo: info(), currentAppURL: current))
    }

    func testVersionNewerThanAdvertisedIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = try makeApp(in: directory, name: "current", version: "1.0")
        let staged = try makeApp(in: directory, name: "staged", version: "3.0")
        XCTAssertThrowsError(try AppUpdateService().verifyStagedApp(staged, expectedInfo: info(), currentAppURL: current))
    }

    func testArchiveDigestAcceptsOriginalAndRejectsTamperingAndMissingDigest() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = Data("isolated update fixture".utf8)
        try bytes.write(to: file)
        let sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let sha512 = Data(SHA512.hash(data: bytes)).base64EncodedString()
        let service = AppUpdateService()
        XCTAssertNoThrow(try service.verifyArchive(file, digest: "sha256:" + sha256))
        XCTAssertNoThrow(try service.verifyArchive(file, digest: "sha512:" + sha512))
        XCTAssertThrowsError(try service.verifyArchive(file, digest: nil))
        XCTAssertThrowsError(try service.verifyArchive(file, digest: "sha256:invalid"))
        try Data("tampered".utf8).write(to: file)
        XCTAssertThrowsError(try service.verifyArchive(file, digest: "sha256:" + sha256))
        XCTAssertThrowsError(try service.verifyArchive(file, digest: "sha512:" + sha512))
    }

    private func info() -> AppUpdateInfo {
        AppUpdateInfo(version: "2.0", releaseName: "Test", releaseNotes: "", publishedAt: nil,
                      htmlURL: URL(string: "https://example.invalid/release")!, downloadURL: nil)
    }

    private func makeApp(in directory: URL, name: String, version: String) throws -> URL {
        let app = directory.appending(path: name + ".app")
        let contents = app.appending(path: "Contents")
        let macOS = contents.appending(path: "MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appending(path: "Fixture"))
        let plist = ["CFBundleIdentifier": "test.fund-pulse.update", "CFBundleExecutable": "Fixture",
                     "CFBundlePackageType": "APPL", "CFBundleVersion": version, "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", app.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return app
    }
}

private final class UpdateFeedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let isAPI = url.host == "api.github.com"
        let responseURL = url.path.hasSuffix("/latest") && !isAPI
            ? URL(string: "https://github.com/iamzjt-front-end/fund-pulse/releases/tag/v2.0")! : url
        let text = """
        version: 2.0
        files:
          - url: fund-pulse-arm64-swift.zip
            sha512: zip-digest
          - url: fund-pulse-arm64-swift.dmg
            sha512: dmg-digest
        sha512: top-level-digest
        """
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: responseURL, statusCode: isAPI ? 503 : 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
