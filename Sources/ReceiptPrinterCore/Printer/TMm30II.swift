public extension PrinterModel {
    /// Verified on hardware (80 mm): USB descriptors, status query and raster printing.
    static let tmM30II80mm = PrinterModel(
        name: "EPSON TM-m30II",
        usbVendorID: 0x04B8,
        usbProductNames: ["TM-m30II"],
        dpi: 203,
        paperWidthMM: 80,
        printableWidthMM: 72,
        dotsPerLine: 576,
        cutMode: .partial,
        cutFeedUnits: 0
    )
}
