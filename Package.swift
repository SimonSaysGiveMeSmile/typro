// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Typro",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Typro", targets: ["Typro"]),
        .executable(name: "typro-fix", targets: ["TyproFix"])
    ],
    targets: [
        .executableTarget(
            name: "Typro",
            path: "Sources/Typro"
        ),
        .executableTarget(
            name: "TyproFix",
            path: "Sources/TyproFix"
        )
    ]
)
