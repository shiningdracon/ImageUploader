#if os(Linux)
    import Glibc
    import Cgdlinux
#else
    import Darwin
    import Cgdmac
#endif
import Foundation
import SwiftGD
import Cryptor


public class ImageUploader {
    public enum ImageUploadError: Error {
        case IOError(String)
        case TypeError
        case SizeError
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
    let maxDimensions: Int

    init(maxDimensions: Int, imageVersions: Array<ImageOptions>) {
        self.imageVersions = imageVersions
        self.maxDimensions = maxDimensions
    }

    func uploadByFile(path: String, localMainName: String) throws -> Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> {

        let fileUrl = URL(fileURLWithPath: path)

        let (width, height, fileExtension) = try getImageInfo(path: path)

        let dimensions: Int = Int(width) * Int(height)
        if dimensions > maxDimensions {
            throw ImageUploadError.SizeError
        }

        if let image = Image(url: fileUrl) {
            return try saveImage(image: image, ext: fileExtension, localMainName: localMainName)
        } else {
            throw ImageUploadError.ValidationError
        }
    }

    func uploadByBase64(base64: String, localMainName: String) {

    }

    func uploadByRemote(url: String, localMainName: String) {

    }

    private func saveImage(image: Image, ext: ImageTypes, localMainName: String) throws -> Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> {

        let (width, height) = image.size

        var infos: Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> = []
        for option in imageVersions {
            let fullName = localMainName + "_" + option.nameSufix + "." + ext.rawValue
            let fullPath = option.uploadDir + "/" + fullName
            let fileUrl = URL(fileURLWithPath: fullPath)

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
                            if resizedWidth >= resizedHeight * 3 {
                                // wide picture (may be a comic), and we are very likely generating a thumbnail, use head part
                                cropX = 0
                            } else {
                                // for normal picture, use middle part
                                cropX = (resizedWidth - option.maxWidth) / 2
                            }
                            adjustedImage = adjustedImage!.crop(x: cropX, y: 0, width: option.maxWidth, height: resizedHeight)
                        }
                    } else {
                        adjustedImage = image.resizedTo(width: option.maxWidth, applySmoothing: true)
                        if adjustedImage != nil {
                            let (resizedWidth, resizedHeight) = adjustedImage!.size
                            let cropY: Int
                            if resizedHeight >= resizedWidth * 3 {
                                // long picture (may be a comic), and we are very likely generating a thumbnail, use head part
                                cropY = 0
                            } else {
                                // for normal picture, use middle part
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


            let (newWidth, newHeight) = adjustedImage!.size

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

            infos.append((fullPath, fullName, Int(size), hash, newWidth, newHeight))
        }

        return infos
    }

    private func getImageInfo(path: String) throws -> (width: UInt32, height: UInt32, type: ImageTypes) {
        let inputFile = fopen(path, "rb")
        if inputFile == nil {
            throw ImageUploadError.IOError("Open file error")
        }

        defer {
            if inputFile != nil {
                fclose(inputFile)
            }
        }


        let buffer = [UInt8](repeating: 0, count: 48)
        if fread(UnsafeMutablePointer(mutating: buffer), buffer.count, 1, inputFile) == 1 {
            if isHeaderPng(bytes: buffer) {
                let width = (UnsafeRawPointer(buffer) + 16).bindMemory(to: UInt32.self, capacity: 1).pointee.bigEndian
                let height = (UnsafeRawPointer(buffer) + 20).bindMemory(to: UInt32.self, capacity: 1).pointee.bigEndian
                return (width, height, ImageTypes.png)
            } else { //TODO: jpg
                throw ImageUploadError.TypeError
            }
        } else {
            throw ImageUploadError.IOError("Read file error")
        }
    }

    private func isHeaderPng(bytes: [UInt8]) -> Bool {
        let pngHeader:[UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        if bytes.count < pngHeader.count {
            return false
        }
        for x in 0 ..< pngHeader.count {
            let byte = bytes[x]
            let header = pngHeader[x]
            if byte != header {
                return false
            }
        }

        return true
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
