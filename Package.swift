// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RFGEN44-App",
    platforms: [.macOS(.v14)],
    products: [
        // Standalone SwiftUI .app (bundled by scripts/build-app.sh)
        .executable(name: "RFGEN44App", targets: ["RFGEN44App"]),
        // Command-line tool, parity with upstream PythonApplication/rfgen44.py
        .executable(name: "rfgen44", targets: ["rfgen44CLI"]),
        // Protocol + ADF4351 maths + IOKit HID transport, no UI
        .library(name: "RFGen44Kit", targets: ["RFGen44Kit"]),
    ],
    targets: [
        .target(
            name: "RFGen44Kit",
            path: "Sources/RFGen44Kit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "RFGEN44App",
            dependencies: ["RFGen44Kit"],
            path: "Sources/RFGEN44App"
        ),
        .executableTarget(
            name: "rfgen44CLI",
            dependencies: ["RFGen44Kit"],
            path: "Sources/rfgen44CLI"
        ),
        .testTarget(
            name: "RFGen44KitTests",
            dependencies: ["RFGen44Kit"],
            path: "Tests/RFGen44KitTests"
        ),
    ]
)
