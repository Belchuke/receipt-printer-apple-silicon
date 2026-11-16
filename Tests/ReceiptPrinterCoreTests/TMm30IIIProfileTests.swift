import Foundation
import Testing
@testable import ReceiptPrinterCore

struct TMm30IIIProfileTests {
    static let density: [UInt8] = [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 127]
    static let speed: [UInt8] = [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x32, 6]

    func contains(_ data: Data, _ pattern: [UInt8]) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= pattern.count else { return false }
        return (0...(bytes.count - pattern.count)).contains { Array(bytes[$0..<($0 + pattern.count)]) == pattern }
    }

    func blackDots(_ bitmap: MonoBitmap) -> Int {
        (0..<bitmap.height).reduce(0) { total, y in total + (0..<bitmap.width).filter { bitmap.isBlack(x: $0, y: y) }.count }
    }

    @Test func profileMatchesTheHardwareAndTunedSettings() {
        let model = PrinterModel.tmM30III80mm
        #expect(model.usbVendorID == 0x04B8 && model.usbProductNames == ["TM-m30III"])
        #expect(model.dpi == 203 && model.dotsPerLine == 576 && model.paperWidthMM == 80)
        #expect(model.effectivePrintDensity(userChoice: nil) == 127)
        #expect(model.effectivePrintSpeed == 6)
        #expect(model.defaultGamma == 2.2)
    }

    @Test func otherPrintersAreLeftAlone() {
        for model in [PrinterModel.tmT88V80mm, .tmT88V58mm, .tmM30II80mm] {
            #expect(model.effectivePrintSpeed == nil, "\(model.name) never receives the speed command")
            #expect(model.defaultGamma == 1.0, "\(model.name) keeps its images unchanged")
            #expect(model.rasterOptions.gamma == 1.0)
        }
        #expect(PrinterModel.tmT88VII80mm.effectivePrintSpeed == nil)
        #expect(PrinterModel.tmT88VII80mm.defaultGamma == 1.0)
    }

    func printed(model: PrinterModel) throws -> Data {
        let out = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: out) }
        var service = PrintService(model: model, output: SinkOutput(path: out.path))
        service.density = { model.effectivePrintDensity(userChoice: nil) }
        // A mid-grey page: the tone curve decides how many dots it gets.
        let page = Fixture.urf(width: 510, height: 60) { _, _ in 170 }
        _ = try service.print(document: page, declaredFormat: "image/urf", jobID: 1)
        return try Data(contentsOf: out.appendingPathComponent("job-1.escpos"))
    }

    @Test func serviceSendsDensityAndSpeedForTheTMm30IIIBeforeTheRaster() throws {
        let bytes = [UInt8](try printed(model: .tmM30III80mm))
        #expect(Array(bytes.prefix(2)) == [0x1B, 0x40])
        #expect(Array(bytes[5..<12]) == Self.density)
        #expect(Array(bytes[12..<19]) == Self.speed)
        #expect(Array(bytes[19..<22]) == [0x1D, 0x76, 0x30], "the raster follows both commands")
    }

    @Test func otherPrintersNeverGetTheSpeedCommand() throws {
        for model in [PrinterModel.tmT88V80mm, .tmT88VII80mm, .tmM30II80mm] {
            #expect(!contains(try printed(model: model), [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x32]))
        }
    }

    @Test func pagesArePrintedDarkerThanOnAPrinterWithoutTheToneCurve() throws {
        func dots(_ model: PrinterModel) throws -> Int {
            let out = SinkOutputTests.scratchDirectory()
            defer { try? FileManager.default.removeItem(at: out) }
            let service = PrintService(model: model, output: SinkOutput(path: out.path))
            _ = try service.print(document: Fixture.urf(width: 510, height: 60) { _, _ in 170 }, declaredFormat: "image/urf", jobID: 1)
            let receipts = try EscPosRasterDecoder.decode(Data(contentsOf: out.appendingPathComponent("job-1.escpos")))
            return blackDots(try #require(receipts.first).bitmap)
        }
        // Same 576-dot geometry; only the tone curve differs.
        #expect(try dots(.tmM30III80mm) > (try dots(.tmM30II80mm)) * 3 / 2)
    }

    @Test func theLogoGetsTheSameToneCurveAsThePage() throws {
        let dir = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("grey.png")
        // A mid-grey logo, like a photo or an anti-aliased mark: the tone curve changes how many dots it prints.
        let grey = GrayImage(width: 240, height: 120, fill: 170)
        try TestPattern.writePNG(try #require(RasterProcessor.cgImage(grey)), to: source)
        let store = SettingsStore(directory: dir.appendingPathComponent("settings"))
        _ = try store.setLogo(from: source, model: .tmM30III80mm)

        let dark = try #require(LogoRenderer.previewBitmap(model: .tmM30III80mm, store: store))
        let plain = try #require(LogoRenderer.previewBitmap(model: .tmM30II80mm, store: store))
        #expect(dark.width == 576 && plain.width == 576)
        #expect(blackDots(dark) > blackDots(plain) * 3 / 2, "the TM-m30III logo is darkened like its pages")
        #expect(LogoRenderer.previewImage(model: .tmM30III80mm, store: store) != nil)
    }

    @Test func aLogoStillStacksAtTheConfiguredPositionOnThisPrinter() throws {
        let dir = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("logo.png")
        try TestPattern.writePNG(try #require(TestPattern.make(width: 300)), to: source)
        let store = SettingsStore(directory: dir.appendingPathComponent("settings"))
        _ = try store.setLogo(from: source, model: .tmM30III80mm)
        _ = try store.setGap(20)

        func printHeight(position: LogoPosition) throws -> (height: Int, firstRowBlack: Bool) {
            _ = try store.setPosition(position)
            let out = SinkOutputTests.scratchDirectory()
            defer { try? FileManager.default.removeItem(at: out) }
            var service = PrintService(model: .tmM30III80mm, output: SinkOutput(path: out.path))
            service.logo = { LogoRenderer.logo(model: .tmM30III80mm, store: store) }
            _ = try service.print(document: Fixture.urf(width: 570, height: 30) { _, _ in 0 }, declaredFormat: "image/urf", jobID: 1)
            let receipts = try EscPosRasterDecoder.decode(Data(contentsOf: out.appendingPathComponent("job-1.escpos")))
            let bitmap = try #require(receipts.first).bitmap
            return (bitmap.height, (10..<566).allSatisfy { bitmap.isBlack(x: $0, y: 0) })
        }
        let logoHeight = try #require(LogoRenderer.previewBitmap(model: .tmM30III80mm, store: store)).height
        let top = try printHeight(position: .top)
        let bottom = try printHeight(position: .bottom)
        #expect(top.height == logoHeight + 20 + 30 && bottom.height == top.height)
        #expect(bottom.firstRowBlack, "at the bottom the receipt (a solid black page) comes first")
        #expect(!top.firstRowBlack, "at the top the logo comes first")
    }
}
