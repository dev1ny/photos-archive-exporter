// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotosArchiveExporter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PhotosArchiveExporterCore",
            targets: ["PhotosArchiveExporterCore"]
        ),
        .executable(
            name: "PhotosArchiveExporterApp",
            targets: ["PhotosArchiveExporterApp"]
        )
    ],
    targets: [
        .target(
            name: "PhotosArchiveExporterCore"
        ),
        .executableTarget(
            name: "PhotosArchiveExporterApp",
            dependencies: ["PhotosArchiveExporterCore"]
        ),
        .testTarget(
            name: "PhotosArchiveExporterCoreTests",
            dependencies: ["PhotosArchiveExporterCore"]
        )
    ]
)
