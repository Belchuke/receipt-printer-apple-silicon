import Foundation

public enum TestReceipt {
    public static func build(model: PrinterModel, details: [String] = []) -> Data {
        let encoder = EscPosEncoder()
        encoder.initialize()
        if let density = model.effectivePrintDensity(userChoice: nil) { encoder.printDensity(density) }
        encoder
            .align(.center)
            .bold(true)
            .line("RECEIPT PRINTER TEST")
            .bold(false)
            .line("Native Apple Silicon printing works.")
            .line()
            .align(.left)

        for detail in details {
            encoder.line(detail)
        }

        encoder.feed(lines: 3)
        encoder.cut(model.cutMode, feedUnits: model.cutFeedUnits)
        return encoder.data
    }
}
