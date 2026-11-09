import Foundation

public enum CutMode: String, Sendable {
    case none
    case partial
    case full
}

public struct PrinterModel: Sendable, Equatable {
    public var name: String
    public var usbVendorID: UInt16
    public var usbProductNames: [String]
    public var dpi: Int
    public var paperWidthMM: Double
    public var printableWidthMM: Double
    public var dotsPerLine: Int
    public var cutMode: CutMode
    public var cutFeedUnits: Int
    /// True only for printers verified to accept GS ( K 49 (select print density). Others never receive the command:
    /// an unsupported printer might print its bytes as text.
    public var supportsPrintDensity: Bool
    /// Density sent when the user has not chosen one (nil = leave the printer's own setting alone).
    public var defaultPrintDensity: UInt8?

    public init(
        name: String,
        usbVendorID: UInt16,
        usbProductNames: [String],
        dpi: Int,
        paperWidthMM: Double,
        printableWidthMM: Double,
        dotsPerLine: Int,
        cutMode: CutMode,
        cutFeedUnits: Int,
        supportsPrintDensity: Bool = false,
        defaultPrintDensity: UInt8? = nil
    ) {
        self.name = name
        self.usbVendorID = usbVendorID
        self.usbProductNames = usbProductNames
        self.dpi = dpi
        self.paperWidthMM = paperWidthMM
        self.printableWidthMM = printableWidthMM
        self.dotsPerLine = dotsPerLine
        self.cutMode = cutMode
        self.cutFeedUnits = cutFeedUnits
        self.supportsPrintDensity = supportsPrintDensity
        self.defaultPrintDensity = defaultPrintDensity
    }

    public static let maxPrintDensity = 127

    /// The density to send for this printer: the user's choice, else the model default; nil when unsupported or unset.
    public func effectivePrintDensity(userChoice: Int?) -> UInt8? {
        guard supportsPrintDensity else { return nil }
        if let userChoice { return UInt8(max(0, min(userChoice, Self.maxPrintDensity))) }
        return defaultPrintDensity
    }

    public func matches(productName: String?) -> Bool {
        guard let productName else { return false }
        let normalized = productName.trimmingCharacters(in: .whitespaces).uppercased()
        return usbProductNames.contains { $0.uppercased() == normalized }
    }
}
