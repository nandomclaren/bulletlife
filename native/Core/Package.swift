// swift-tools-version: 5.9
// Bullet Life's platform-independent core: the data model, dates, the line rules and the pen's line
// rules, ported from the PWA (src/) so both read and write the same data. No UI, no Apple-only APIs:
// it builds and tests anywhere Swift runs (`swift test`).
import PackageDescription

let package = Package(
    name: "BulletLifeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BulletLifeCore", targets: ["BulletLifeCore"])],
    targets: [
        .target(name: "BulletLifeCore"),
        .testTarget(name: "BulletLifeCoreTests", dependencies: ["BulletLifeCore"]),
    ]
)
