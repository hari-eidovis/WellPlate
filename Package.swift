// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WellPlatePlaygrounds",
    defaultLocalization: "en",
    platforms: [
        .iOS("18.1"),
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "WellPlatePlaygrounds",
            targets: ["WellPlatePlaygrounds"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "WellPlatePlaygrounds",
            path: "PlaygroundsSupport/Sources"
        ),
    ]
)
