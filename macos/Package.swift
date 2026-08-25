// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QRKeyboardHost",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "QRKeyboardHost",
            path: "Sources/QRKeyboardHost"
        )
    ]
)
