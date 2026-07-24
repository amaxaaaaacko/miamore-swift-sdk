// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

func sdkPath(_ sdk: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--sdk", sdk, "--show-sdk-path"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}

func fileContains(_ path: String, _ needle: String) -> Bool {
    guard let data = FileManager.default.contents(atPath: path),
          let text = String(data: data, encoding: .utf8) else { return false }
    return text.contains(needle)
}

func storeKitSupportsBillingPlanType() -> Bool {
    let sdks = ["iphoneos", "iphonesimulator", "macosx", "appletvos", "appletvsimulator", "xros", "xrsimulator"]

    for sdk in sdks {
        guard let root = sdkPath(sdk) else { continue }
        let moduleDir = root + "/System/Library/Frameworks/StoreKit.framework/Modules/StoreKit.swiftmodule"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: moduleDir) else { continue }
        for file in files where file.hasSuffix(".swiftinterface") {
            if fileContains(moduleDir + "/" + file, "billingPlanType") {
                return true
            }
        }
    }
    return false
}

let swiftSettings: [SwiftSetting] = storeKitSupportsBillingPlanType()
    ? [.define("MIAMORE_ENABLE_STOREKIT_COMMITMENT_PLANS")]
    : []

let package = Package(
    name: "miamore-swift-sdk",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "miamore-swift-sdk",
            targets: ["miamore-swift-sdk"]
        ),
    ],
    targets: [
        .target(
            name: "miamore-swift-sdk",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "miamore-swift-sdkTests",
            dependencies: ["miamore-swift-sdk"]
        ),
    ]
)
