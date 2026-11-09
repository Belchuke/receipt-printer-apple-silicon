import Foundation
import Testing
@testable import ReceiptPrinterCore

struct PrintDensityModelTests {
    static let densityCommand: [UInt8] = [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31]

    func contains(_ data: Data, _ pattern: [UInt8]) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= pattern.count else { return false }
        return (0...(bytes.count - pattern.count)).contains { Array(bytes[$0..<($0 + pattern.count)]) == pattern }
    }

    @Test func onlyTheTM_T88VIISendsDensityByDefault() {
        #expect(PrinterModel.tmT88VII80mm.supportsPrintDensity)
        #expect(PrinterModel.tmT88VII80mm.effectivePrintDensity(userChoice: nil) == 127)
        for model in [PrinterModel.tmT88V80mm, .tmT88V58mm, .tmM30II80mm] {
            #expect(!model.supportsPrintDensity)
            #expect(model.effectivePrintDensity(userChoice: nil) == nil)
            #expect(model.effectivePrintDensity(userChoice: 80) == nil, "never sent to a printer not verified to accept it")
        }
    }

    @Test func userChoiceOverridesTheDefaultAndIsClamped() {
        let model = PrinterModel.tmT88VII80mm
        #expect(model.effectivePrintDensity(userChoice: 0) == 0)
        #expect(model.effectivePrintDensity(userChoice: 60) == 60)
        #expect(model.effectivePrintDensity(userChoice: 5_000) == 127)
        #expect(model.effectivePrintDensity(userChoice: -3) == 0)
    }

    @Test func settingsStoreDensityRoundTrip() throws {
        let dir = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)
        #expect(store.effectivePrintDensity(for: .tmT88VII80mm) == 127)
        #expect(try store.setDensity(70).density == 70)
        #expect(store.effectivePrintDensity(for: .tmT88VII80mm) == 70)
        #expect(store.effectivePrintDensity(for: .tmM30II80mm) == nil)
        #expect(try store.setDensity(9_999).density == 127)
        #expect(try store.setDensity(nil).density == nil)
        #expect(store.effectivePrintDensity(for: .tmT88VII80mm) == 127)
        let text = try String(contentsOf: store.settingsURL, encoding: .utf8)
        #expect(!text.contains("density"), "an unset density is not written")
    }

    @Test func settingsFileWithBadDensityFallsBackToTheDefault() throws {
        let dir = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)
        try Data("{\"model\":\"tm-t88vii\",\"density\":\"lots\"}".utf8).write(to: store.settingsURL)
        #expect(store.load().model == "tm-t88vii" && store.load().density == nil)
    }

    func printed(model: PrinterModel, density: UInt8?) throws -> Data {
        let out = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: out) }
        var service = PrintService(model: model, output: SinkOutput(path: out.path))
        service.density = { density }
        let page = Fixture.urf(width: 510, height: 40) { _, _ in 0 }
        _ = try service.print(document: page, declaredFormat: "image/urf", jobID: 1)
        return try Data(contentsOf: out.appendingPathComponent("job-1.escpos"))
    }

    @Test func serviceSendsTheDensityAfterInitializeAndBeforeTheRaster() throws {
        let data = try printed(model: .tmT88VII80mm, density: 127)
        let bytes = [UInt8](data)
        #expect(Array(bytes.prefix(2)) == [0x1B, 0x40])
        #expect(Array(bytes[5..<12]) == Self.densityCommand + [127])
        #expect(Array(bytes[12..<15]) == [0x1D, 0x76, 0x30], "the raster follows the density command")
    }

    @Test func serviceSendsNoDensityCommandWhenNoneIsSet() throws {
        #expect(!contains(try printed(model: .tmM30II80mm, density: nil), Self.densityCommand))
        #expect(!contains(try printed(model: .tmT88V80mm, density: nil), Self.densityCommand))
    }

    @Test func testReceiptUsesTheModelDefaultDensity() {
        #expect(contains(TestReceipt.build(model: .tmT88VII80mm), Self.densityCommand + [127]))
        #expect(!contains(TestReceipt.build(model: .tmT88V80mm), Self.densityCommand))
    }

    @Test func registryHasAllThreePrinters() {
        #expect(PrinterModel.registryIDs == ["tm-t88v", "tm-t88vii", "tm-m30ii"])
        #expect(PrinterModel.named("TM-T88VII") == .tmT88VII80mm)
        #expect(PrinterModel.tmT88VII80mm.matches(productName: "TM-T88VII "))
        #expect(!PrinterModel.tmT88V80mm.matches(productName: "TM-T88VII"), "the two TM-T88 models must not match each other")
        #expect(!PrinterModel.tmT88VII80mm.matches(productName: "TM-T88V"))
    }
}
