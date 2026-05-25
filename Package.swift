// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CadencePlaygrounds",
    defaultLocalization: "en",
    platforms: [
        .iOS("18.1"),
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "CadencePlaygrounds",
            targets: ["CadencePlaygrounds"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "CadencePlaygrounds",
            path: "PlaygroundsSupport/Sources"
        ),
    ]
)
