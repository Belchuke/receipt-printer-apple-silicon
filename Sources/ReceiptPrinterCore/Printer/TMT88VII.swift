public extension PrinterModel {
    /// USB identity read from hardware (0x04B8:0x0E2D, "TM-T88VII", Printer Class, bulk 0x01 OUT / 0x82 IN).
    /// Print width and resolution follow the TM-T88 family (80 mm paper, 72 mm print width at 180 dpi); confirm with a ruler print.
    static let tmT88VII80mm = PrinterModel(
        name: "EPSON TM-T88VII",
        usbVendorID: 0x04B8,
        usbProductNames: ["TM-T88VII"],
        dpi: 180,
        paperWidthMM: 80,
        printableWidthMM: 72,
        dotsPerLine: 512,
        cutMode: .partial,
        cutFeedUnits: 0,
        // Epson lists GS ( K 49 for the TM-T88VII. On this printer the default print was too pale to read 12 pt text;
        // the strongest setting (127) printed well on hardware.
        supportsPrintDensity: true,
        defaultPrintDensity: 127
    )
}
