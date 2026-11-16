public extension PrinterModel {
    /// USB identity read from hardware (0x04B8:0x0E32, "TM-m30III", Printer Class, bulk 0x01 OUT / 0x82 IN).
    /// Geometry follows the TM-m30 family (80 mm paper, 72 mm print width at 203 dpi); a ruler print on hardware confirmed it.
    /// Out of the box this printer printed pale and grey. Tuned on hardware with test patterns: density 127 (the top of the
    /// command's range), speed level 6 and a gamma 2.2 tone curve together gave solid black and readable small text.
    /// Gamma 2.6 clogged small text; speed 1 was slower than needed.
    static let tmM30III80mm = PrinterModel(
        name: "EPSON TM-m30III",
        usbVendorID: 0x04B8,
        usbProductNames: ["TM-m30III"],
        dpi: 203,
        paperWidthMM: 80,
        printableWidthMM: 72,
        dotsPerLine: 576,
        cutMode: .partial,
        cutFeedUnits: 0,
        supportsPrintDensity: true,
        defaultPrintDensity: 127,
        supportsPrintSpeed: true,
        defaultPrintSpeed: 6,
        defaultGamma: 2.2
    )
}
