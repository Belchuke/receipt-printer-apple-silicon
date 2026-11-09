import Testing
@testable import ReceiptPrinterCore

struct ModelRegistryTests {
    @Test func looksUpModelsCaseInsensitively() {
        #expect(PrinterModel.named("tm-t88v") == .tmT88V80mm)
        #expect(PrinterModel.named("TM-m30II") == .tmM30II80mm)
        #expect(PrinterModel.named("unknown") == nil)
    }

    @Test func m30IIProfileMatchesCapturedUsbIdentity() {
        let model = PrinterModel.tmM30II80mm
        #expect(model.usbVendorID == 0x04B8)
        #expect(model.matches(productName: "TM-m30II"))
        #expect(!model.matches(productName: "TM-T88V"))
        #expect(model.dotsPerLine == 576 && model.dpi == 203)
    }
}
