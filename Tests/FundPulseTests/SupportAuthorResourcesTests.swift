import AppKit
import Foundation
import ImageIO
import SwiftUI
import Vision
import XCTest
@testable import FundPulse

final class SupportAuthorResourcesTests: XCTestCase {
    func testSupportCopyIsWarmAndKeepsTheVoluntaryBoundary() {
        XCTAssertEqual(
            SupportAuthorCopy.motivation,
            "Fund Pulse 免费、开源且无广告。您的支持，是我持续更新、修复问题和适配新版 macOS 的最大动力。感谢您的认可与鼓励。"
        )
        XCTAssertTrue(SupportAuthorCopy.paymentBoundary.contains("支持完全自愿"))
        XCTAssertTrue(SupportAuthorCopy.paymentBoundary.contains("不会解锁额外功能"))
        XCTAssertTrue(SupportAuthorCopy.paymentBoundary.contains("不读取、上传或保存支付信息"))
    }

    func testSupportImagesLoadWithExpectedDimensionsAndNoPersonalMetadata() throws {
        let expectedSizes: [SupportAuthorAsset: (width: Int, height: Int)] = [
            .wechat: (828, 1124),
            .alipay: (1708, 2560)
        ]

        for asset in SupportAuthorAsset.allCases {
            let url = try XCTUnwrap(SupportAuthorResources.url(for: asset))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            )
            let expectedSize = try XCTUnwrap(expectedSizes[asset])

            XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, expectedSize.width)
            XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, expectedSize.height)
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary])

            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal])
            XCTAssertNil(exif?[kCGImagePropertyExifUserComment])

            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            XCTAssertNil(tiff?[kCGImagePropertyTIFFMake])
            XCTAssertNil(tiff?[kCGImagePropertyTIFFModel])
            XCTAssertNil(tiff?[kCGImagePropertyTIFFArtist])
            XCTAssertNil(tiff?[kCGImagePropertyTIFFCopyright])
        }
    }

    func testEachSupportImageContainsExactlyOneQRCodeWithoutReadingItsPayload() throws {
        for asset in SupportAuthorAsset.allCases {
            let url = try XCTUnwrap(SupportAuthorResources.url(for: asset))
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]

            try VNImageRequestHandler(url: url).perform([request])

            XCTAssertEqual(request.results?.count, 1, "\(asset.rawValue) 应恰好识别出一个二维码")
        }
    }

    func testPaymentTabsUseWechatThenAlipay() {
        XCTAssertEqual(SupportAuthorAsset.allCases, [.wechat, .alipay])
        XCTAssertEqual(SupportAuthorAsset.allCases.map(\.title), ["微信支付", "支付宝"])
    }

    func testEmbeddedSupportSectionDisplaysThePosterWithoutAnotherCardFrame() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/FundPulse/Views/SupportAuthorSection.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("private var paymentCard"))
        XCTAssertFalse(source.contains("PanelDesign.inputBackground"))
        XCTAssertFalse(source.contains("请使用\\(selectedAsset.scanAppName)扫一扫"))
    }

    @MainActor
    func testEmbeddedSupportSectionRendersBothPaymentMethodsInLightAndDarkAppearances() throws {
        let appearances: [(name: String, scheme: ColorScheme)] = [
            ("light", .light),
            ("dark", .dark)
        ]

        for appearance in appearances {
            for asset in SupportAuthorAsset.allCases {
                let renderer = ImageRenderer(
                    content: SupportAuthorSection(initialAsset: asset)
                        .frame(width: 312)
                        .preferredColorScheme(appearance.scheme)
                )
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)

                XCTAssertEqual(image.size.width, 312)
                XCTAssertGreaterThan(image.size.height, 300)
                XCTAssertLessThanOrEqual(image.size.height, 540)

                if ProcessInfo.processInfo.environment["FUND_PULSE_CAPTURE_SUPPORT_AUTHOR"] == "1" {
                    let tiff = try XCTUnwrap(image.tiffRepresentation)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try png.write(
                        to: FileManager.default.temporaryDirectory.appending(
                            path: "fund-pulse-support-\(asset.rawValue)-\(appearance.name).png"
                        ),
                        options: .atomic
                    )
                }
            }
        }
    }
}
