// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "ImageUploader",
    dependencies: [
        .Package(url: "https://github.com/shiningdracon/SwiftGD.git", majorVersion: 1),
        .Package(url: "https://github.com/IBM-Swift/BlueCryptor.git", majorVersion: 0),
    ]
)
