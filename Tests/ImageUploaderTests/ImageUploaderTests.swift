import XCTest
@testable import ImageUploader

class ImageUploaderTests: XCTestCase {
    struct TestHelper {
        static let pngBase64 = ""

        static func writePNG() -> URL? {
            return writeImage(base64: pngBase64, name: "image.png")
        }

        static func writeImage(base64:String, name:String) -> URL? {
            let data = Data(base64Encoded: base64)
            var url = URL(fileURLWithPath: NSTemporaryDirectory())
            url.appendPathComponent(name)
            do {
                try data?.write(to: url)
            } catch let error {
                print("\(error)")
                return nil
            }
            return url
        }
        
    }

    func testUploadByFile() {
        let uploader = ImageUploader(maxDimensions: 100 * 100,
                                     imageVersions: [
                                        ImageUploader.ImageOptions(
                                            uploadDir: "",
                                            nameSufix: "",
                                            maxWidth: 10,
                                            maxHeight: 10,
                                            quality: 100,
                                            rotateByExif: false,
                                            crop: false
                                        )])
        do {
            try uploader.uploadByFile(path: "2.jpg", localMainName: "123")
        } catch {

        }
    }


    static var allTests = [
        ("testUploadByFile", testUploadByFile),
    ]
}
