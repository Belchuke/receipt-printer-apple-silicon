// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReceiptPrinter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "receipt-printer-diag", targets: ["receipt-printer-diag"]),
        .executable(name: "receipt-printer-test", targets: ["receipt-printer-test"]),
        .executable(name: "receipt-printer-raster-test", targets: ["receipt-printer-raster-test"]),
        .executable(name: "receipt-printer-service", targets: ["receipt-printer-service"]),
        .executable(name: "receipt-printer-settings", targets: ["receipt-printer-settings"]),
        .executable(name: "receipt-printer-config", targets: ["receipt-printer-config"]),
        .executable(name: "receipt-printer-updater", targets: ["receipt-printer-updater"]),
    ],
    targets: [
        .target(
            name: "ReceiptPrinterCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("ImageIO"),
            ]
        ),
        .executableTarget(name: "receipt-printer-diag", dependencies: ["ReceiptPrinterCore"]),
        .executableTarget(name: "receipt-printer-test", dependencies: ["ReceiptPrinterCore"]),
        .executableTarget(name: "receipt-printer-raster-test", dependencies: ["ReceiptPrinterCore"]),
        .executableTarget(name: "receipt-printer-service", dependencies: ["ReceiptPrinterCore"]),
        .executableTarget(name: "receipt-printer-settings", dependencies: ["ReceiptPrinterCore"]),
        .executableTarget(name: "receipt-printer-config", dependencies: ["ReceiptPrinterCore"]),
        .target(name: "ReceiptPrinterUpdater"),
        .executableTarget(name: "receipt-printer-updater", dependencies: ["ReceiptPrinterUpdater"]),
        .testTarget(name: "ReceiptPrinterCoreTests", dependencies: ["ReceiptPrinterCore"]),
        .testTarget(name: "ReceiptPrinterUpdaterTests", dependencies: ["ReceiptPrinterUpdater"]),
    ]
)
