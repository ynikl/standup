// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StandUp",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "StandUpCore", targets: ["StandUpCore"]),
        .executable(name: "StandUpCoreChecks", targets: ["StandUpCoreChecks"])
    ],
    targets: [
        .target(name: "StandUpCore"),
        .executableTarget(name: "StandUpCoreChecks", dependencies: ["StandUpCore"], path: "Checks/StandUpCoreChecks")
    ]
)
