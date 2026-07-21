import Foundation
import ImageIO
import Vision
import XCTest
@testable import FundPulse

final class ContactAuthorResourcesTests: XCTestCase {
    func testWechatContactImageLoadsWithExpectedDimensionsAndNoPersonalMetadata() throws {
        let url = try XCTUnwrap(ContactAuthorResources.wechatQRCodeURL())
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )

        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 888)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 1131)
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

    func testWechatContactImageContainsExactlyOneQRCodeWithoutReadingItsPayload() throws {
        let url = try XCTUnwrap(ContactAuthorResources.wechatQRCodeURL())
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        try VNImageRequestHandler(url: url).perform([request])

        XCTAssertEqual(request.results?.count, 1, "微信联系图片应恰好识别出一个二维码")
    }
}
