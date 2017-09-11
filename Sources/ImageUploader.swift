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
        case gif = "gif"
    }

    let imageVersions: Array<ImageOptions>
    let maxDimensions: Int

    init(maxDimensions: Int, imageVersions: Array<ImageOptions>) {
        self.imageVersions = imageVersions
        self.maxDimensions = maxDimensions
    }

    func uploadByFile(path: String, localMainName: String) throws -> Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> {

        let fileUrl = URL(fileURLWithPath: path)

        let (fileType, width, height) = try getImageInfo(path: path)

        let dimensions: Int = Int(width) * Int(height)
        if dimensions > maxDimensions {
            throw ImageUploadError.SizeError
        }

        if let image = Image(url: fileUrl) {
            return try saveImage(image: image, type: fileType, localMainName: localMainName)
        } else {
            throw ImageUploadError.ValidationError
        }
    }

    private func saveImage(image: Image, type: ImageTypes, localMainName: String) throws -> Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> {

        let (width, height) = image.size

        var infos: Array<(path: String, name: String, size: Int, hash: String, width: Int, height: Int)> = []
        for option in imageVersions {
            let fullName = localMainName + option.nameSufix + "." + type.rawValue
            let fullPath = option.uploadDir + "/" + fullName
            let fileUrl = URL(fileURLWithPath: fullPath)

            var adjustedImage: Image?
            if width > option.maxWidth && height > option.maxHeight {
                // both width and height oversized, need resize
                if option.crop {
                    // resize to witch out limited less, then crop
                    if width / option.maxWidth > height / option.maxHeight {
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
                    // resize to witch out limited most
                    if width / option.maxWidth > height / option.maxHeight {
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

            switch type {
            case .jpg:
                (data, size) = adjustedImage!.writeToJpegData(quality: option.quality)
            case .png:
                (data, size) = adjustedImage!.writeToPngData()
            case .gif:
                (data, size) = adjustedImage!.writeToGifData()
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

    private func getImageInfo(path: String) throws -> (type: ImageTypes, width: UInt32, height: UInt32) {
        guard let inputFile = fopen(path, "rb") else {
            throw ImageUploadError.IOError("Open file error")
        }

        defer {
            fclose(inputFile)
        }

        let buffer = [UInt8](repeating: 0, count: 8)
        if fread(UnsafeMutablePointer(mutating: buffer), buffer.count, 1, inputFile) == 1 {
            let type = try getImageType(buffer: buffer)
            let width: UInt32, height: UInt32
            switch type {
            case .png:
                let pngBuffer = [UInt8](repeating: 0, count: 8)
                guard fseek(inputFile, 16, SEEK_SET) == 0 else {
                    throw ImageUploadError.IOError("Seek file error")
                }
                guard fread(UnsafeMutablePointer(mutating: pngBuffer), pngBuffer.count, 1, inputFile) == 1 else {
                    throw ImageUploadError.IOError("Read file error")
                }
                width = (UInt32(pngBuffer[0]) << 24) + (UInt32(pngBuffer[1]) << 16) + (UInt32(pngBuffer[2]) << 8) + UInt32(pngBuffer[3])
                height = (UInt32(pngBuffer[4]) << 24) + (UInt32(pngBuffer[5]) << 16) + (UInt32(pngBuffer[6]) << 8) + UInt32(pngBuffer[7])
                return (type, width, height)
            case .jpg:
                let jpgBuffer = [UInt8](repeating: 0, count: 10)
                guard fseek(inputFile, 2, SEEK_SET) == 0 else {
                    throw ImageUploadError.IOError("Seek file error")
                }
                while (true) {
                    guard fread(UnsafeMutablePointer(mutating: jpgBuffer), jpgBuffer.count, 1, inputFile) == 1 else {
                        throw ImageUploadError.IOError("Read file error")
                    }
                    if jpgBuffer[0] == 0xFF {
                        if jpgBuffer[1] == 0xC0 {
                            let sizeSection = Int(UInt16(jpgBuffer[2]) << 8) + Int(jpgBuffer[3])
                            if sizeSection < 8 {
                                throw ImageUploadError.ValidationError
                            }
                            width = UInt32(UInt16(jpgBuffer[5]) << 8) + UInt32(jpgBuffer[6])
                            height = UInt32(UInt16(jpgBuffer[7]) << 8) + UInt32(jpgBuffer[8])
                            return (ImageTypes.jpg, width, height)
                        } else {
                            let sizeSection = Int(UInt16(jpgBuffer[2]) << 8) + Int(jpgBuffer[3])
                            if sizeSection < 2 {
                                throw ImageUploadError.ValidationError
                            }
                            guard fseek(inputFile, 2 + sizeSection - jpgBuffer.count, SEEK_CUR) == 0 else {
                                throw ImageUploadError.IOError("Seek file error")
                            }
                        }
                    } else {
                        throw ImageUploadError.ValidationError
                    }
                }
            case .gif:
                let gifBuffer = [UInt8](repeating: 0, count: 4)
                guard fseek(inputFile, 6, SEEK_SET) == 0 else {
                    throw ImageUploadError.IOError("Seek file error")
                }
                guard fread(UnsafeMutablePointer(mutating: gifBuffer), gifBuffer.count, 1, inputFile) == 1 else {
                    throw ImageUploadError.IOError("Read file error")
                }
                width = UInt32(gifBuffer[0]) + (UInt32(gifBuffer[1]) << 8)
                height = UInt32(gifBuffer[2]) + (UInt32(gifBuffer[3]) << 8)
                return (type, width, height)
            }
        } else {
            throw ImageUploadError.IOError("Read file error")
        }
    }

    private let pngHeader: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    private let jpgHeader: [UInt8] = [0xff, 0xd8, 0xff]
    private let gifHeader: [UInt8] = [0x47, 0x49, 0x46]
    // Detect image type from first bytes
    private func getImageType(buffer: [UInt8]) throws -> ImageTypes {
        if memcmp(UnsafeRawPointer(buffer), UnsafeRawPointer(jpgHeader), 3) == 0 {
            return ImageTypes.jpg
        } else if memcmp(UnsafeRawPointer(buffer), UnsafeRawPointer(gifHeader), 3) == 0 {
            return ImageTypes.gif
        } else if memcmp(UnsafeRawPointer(buffer), UnsafeRawPointer(pngHeader), 8) == 0 {
            return ImageTypes.png
        } else {
            throw ImageUploadError.TypeError
        }
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
