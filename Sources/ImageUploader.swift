import Foundation
import SwiftGD
import Cryptor


public class ImageUploader {
    public enum ImageUploadError: Error {
        case IOError(String)
        case TypeError
        case ValidationError
        case OperationError(String)
    }

    struct ImageOptions {
        let uploadDir: String
        let nameSufix: String
        let maxWidth: Int
        let maxHeight: Int
        let quality: Int
        let rotateByExif: Bool
        let crop: Bool
    }

    enum ImageTypes: String {
        case png = "png"
        case jpg = "jpg"
    }

    let imageVersions: Array<ImageOptions>

    init(imageVersions: Array<ImageOptions>) {
        self.imageVersions = imageVersions
    }

    func uploadByFile(path: String, contentType: String, localMainName: String) throws -> Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> {
        var fileExtension: ImageTypes
        if contentType == "image/jpeg" {
            fileExtension = .jpg
        } else if contentType == "image/png" {
            fileExtension = .png
        } else {
            throw ImageUploadError.TypeError
        }

        if let image = Image(url: URL(fileURLWithPath: path)) {
            return try saveImage(image: image, ext: fileExtension, localMainName: localMainName)
        } else {
            throw ImageUploadError.ValidationError
        }
    }

    func uploadByBase64(base64: String, contentType: String) {

    }

    func uploadByRemote(url: String) {

    }

    private func saveImage(image: Image, ext: ImageTypes, localMainName: String) throws -> Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> {

        var infos: Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> = []
        for option in imageVersions {
            let fullName = localMainName + "_" + option.nameSufix + "." + ext.rawValue
            let fullPath = option.uploadDir + "/" + fullName
            let fileUrl = URL(fileURLWithPath: fullPath)

            var (width, height) = image.size

            var adjustedImage: Image?
            if width > option.maxWidth && height > option.maxHeight {
                // both width and height oversized, need resize
                if option.crop {
                    // resize to short edge, then crop
                    if width > height {
                        adjustedImage = image.resizedTo(height: option.maxHeight, applySmoothing: true)
                        if adjustedImage != nil {
                            let (resizedWidth, resizedHeight) = adjustedImage!.size
                            let cropX: Int
                            if resizedWidth > resizedHeight * 3 {
                                // use head part (may be a comic)
                                cropX = 0
                            } else {
                                // use middle part
                                cropX = (resizedWidth - option.maxWidth) / 2
                            }
                            adjustedImage = adjustedImage!.crop(x: cropX, y: 0, width: option.maxWidth, height: resizedHeight)
                        }
                    } else {
                        adjustedImage = image.resizedTo(width: option.maxWidth, applySmoothing: true)
                        if adjustedImage != nil {
                            let (resizedWidth, resizedHeight) = adjustedImage!.size
                            let cropY: Int
                            if resizedHeight > resizedWidth * 3 {
                                // use head part (may be a comic)
                                cropY = 0
                            } else {
                                // use middle part
                                cropY = (resizedHeight - option.maxHeight) / 2
                            }
                            adjustedImage = adjustedImage!.crop(x: 0, y: cropY, width: resizedWidth, height: option.maxHeight)
                        }
                    }
                } else {
                    // resize to long edge
                    if width > height {
                        adjustedImage = image.resizedTo(width: option.maxWidth, applySmoothing: true)
                    } else {
                        adjustedImage = image.resizedTo(height: option.maxHeight, applySmoothing: true)
                    }
                }
            } else if width > option.maxWidth {
                if option.crop {
                    adjustedImage = image.crop(x: (width - option.maxWidth) / 2, y: 0, width: option.maxWidth, height: height)
                } else {
                    adjustedImage = image.resizedTo(width: option.maxWidth, applySmoothing: true)
                }
            } else if height > option.maxHeight {
                if option.crop {
                    adjustedImage = image.crop(x: 0, y: (height - option.maxHeight) / 2, width: width, height: option.maxHeight)
                } else {
                    adjustedImage = image.resizedTo(height: option.maxHeight, applySmoothing: true)
                }
            } else {
                adjustedImage = image
            }

            if adjustedImage == nil {
                throw ImageUploadError.OperationError("Adjust image failed")
            }


            (width, height) = adjustedImage!.size

            let data: Data?
            let size: Int32

            switch ext {
            case .jpg:
                (data, size) = adjustedImage!.writeToJpegData(quality: option.quality)
            case .png:
                (data, size) = adjustedImage!.writeToPngData()
            }
            if data == nil {
                throw ImageUploadError.OperationError("Generate image failed")
            }

            let hash = CryptoUtils.hexString(from: [UInt8](data!.sha256))

            let fm = FileManager()

            // refuse to overwrite existing files
            guard fm.fileExists(atPath: fileUrl.path) == false else {
                throw ImageUploadError.IOError("File already exist")
            }

            do {
                try data!.write(to: fileUrl)
            } catch {
                throw ImageUploadError.IOError("Write file failed")
            }

            infos.append((fullPath, fullName, Int(size), hash, width, height))
        }

        return infos
    }
}

extension String {
    var filePathSeparator: UnicodeScalar {
        return UnicodeScalar(47)
    }

    var fileExtensionSeparator: UnicodeScalar {
        return UnicodeScalar(46)
    }

    private func lastPathSeparator(in unis: String.CharacterView) -> String.CharacterView.Index {
        let startIndex = unis.startIndex
        var endIndex = unis.endIndex
        while endIndex != startIndex {
            if unis[unis.index(before: endIndex)] != Character(filePathSeparator) {
                break
            }
            endIndex = unis.index(before: endIndex)
        }
        return endIndex
    }

    private func lastExtensionSeparator(in unis: String.CharacterView, endIndex: String.CharacterView.Index) -> String.CharacterView.Index {
        var endIndex = endIndex
        while endIndex != startIndex {
            endIndex = unis.index(before: endIndex)
            if unis[endIndex] == Character(fileExtensionSeparator) {
                break
            }
        }
        return endIndex
    }

    public var filePathExtension: String {
        let unis = self.characters
        let startIndex = unis.startIndex
        var endIndex = lastPathSeparator(in: unis)
        let noTrailsIndex = endIndex
        endIndex = lastExtensionSeparator(in: unis, endIndex: endIndex)
        guard endIndex != startIndex else {
            return ""
        }
        return self[unis.index(after: endIndex)..<noTrailsIndex]
    }
}
