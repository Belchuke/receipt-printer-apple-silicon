import Foundation
import Testing
@testable import ReceiptPrinterCore

struct EscPosEncoderTests {
    @Test func initializeIsEscAt() {
        let encoder = EscPosEncoder()
        encoder.initialize()
        #expect([UInt8](encoder.data) == [0x1B, 0x40])
    }

    @Test func lineAppendsLineFeed() {
        let encoder = EscPosEncoder()
        encoder.line("AB")
        #expect([UInt8](encoder.data) == [0x41, 0x42, 0x0A])
    }

    @Test func nonAsciiIsReplaced() {
        #expect(EscPosEncoder.asciiBytes("æ1") == [UInt8(ascii: "?"), UInt8(ascii: "1")])
    }

    @Test func feedSplitsAbove255() {
        let encoder = EscPosEncoder()
        encoder.feed(lines: 300)
        #expect([UInt8](encoder.data) == [0x1B, 0x64, 255, 0x1B, 0x64, 45])
    }

    @Test func cutCommands() {
        let partial = EscPosEncoder()
        partial.cut(.partial, feedUnits: 3)
        #expect([UInt8](partial.data) == [0x1D, 0x56, 66, 3])

        let full = EscPosEncoder()
        full.cut(.full)
        #expect([UInt8](full.data) == [0x1D, 0x56, 65, 0])

        let none = EscPosEncoder()
        none.cut(.none)
        #expect(none.data.isEmpty)
    }

    @Test func characterSizeClamps() {
        let encoder = EscPosEncoder()
        encoder.characterSize(width: 2, height: 9)
        #expect([UInt8](encoder.data) == [0x1D, 0x21, 0x17])
    }

    @Test func testReceiptStartsWithInitAndEndsWithCut() {
        let bytes = [UInt8](TestReceipt.build(model: .tmT88V80mm))
        #expect(Array(bytes.prefix(2)) == [0x1B, 0x40])
        #expect(Array(bytes.suffix(4)) == [0x1D, 0x56, 66, 0])
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains("RECEIPT PRINTER TEST"))
        #expect(text.contains("Native Apple Silicon printing works."))
    }

    @Test func testReceiptWithoutCutHasNoGsV() {
        var model = PrinterModel.tmT88V80mm
        model.cutMode = .none
        let bytes = [UInt8](TestReceipt.build(model: model))
        #expect(!zip(bytes, bytes.dropFirst()).contains { $0 == 0x1D && $1 == 0x56 })
    }
}

struct PrintDensityTests {
    @Test func densityCommandIsGSParenK49() {
        #expect([UInt8](EscPosEncoder().printDensity(0).data) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 0x00])
        #expect([UInt8](EscPosEncoder().printDensity(127).data) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 0x7F])
        #expect([UInt8](EscPosEncoder().printDensity(200).data) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 0xC8])
    }

    @Test func receiptSendsDensityAfterInitializeAndOnlyWhenAsked() throws {
        let bitmap = MonoBitmap(width: 8, height: 1, data: [0xFF])
        let plain = [UInt8](try RasterReceipt.build(bitmap: bitmap, model: .tmT88VII80mm))
        #expect(!plain.contains(0x31) || !String(decoding: plain, as: UTF8.self).contains("(K"))
        let withDensity = [UInt8](try RasterReceipt.build(bitmap: bitmap, model: .tmT88VII80mm, density: 100))
        #expect(Array(withDensity.prefix(2)) == [0x1B, 0x40], "ESC @ comes first: it would reset the density if it came after")
        #expect(Array(withDensity[5..<12]) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 100])
        #expect(withDensity.count == plain.count + 7)
    }
}

struct PrintSpeedTests {
    @Test func speedCommandIsGSParenK50() {
        #expect([UInt8](EscPosEncoder().printSpeed(1).data) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x32, 0x01])
        #expect([UInt8](EscPosEncoder().printSpeed(17).data) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x32, 0x11])
    }

    @Test func receiptSendsSpeedAfterDensityAndOnlyWhenAsked() throws {
        let bitmap = MonoBitmap(width: 8, height: 1, data: [0xFF])
        let plain = [UInt8](try RasterReceipt.build(bitmap: bitmap, model: .tmM30III80mm))
        let both = [UInt8](try RasterReceipt.build(bitmap: bitmap, model: .tmM30III80mm, density: 127, speed: 3))
        #expect(both.count == plain.count + 14)
        #expect(Array(both[5..<12]) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31, 127])
        #expect(Array(both[12..<19]) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x32, 3])
        let speedOnly = [UInt8](try RasterReceipt.build(bitmap: bitmap, model: .tmM30III80mm, speed: 1))
        #expect(speedOnly.count == plain.count + 7 && Array(speedOnly[5..<12]) == [0x1D, 0x28, 0x4B, 0x02, 0x00, 0x32, 1])
    }
}

struct DecoderSettingsCommandTests {
    @Test func decoderSkipsDensityAndSpeedCommands() throws {
        let bitmap = MonoBitmap(width: 8, height: 2, data: [0xFF, 0x00])
        let payload = try RasterReceipt.build(bitmap: bitmap, model: .tmM30III80mm, density: 127, speed: 6)
        let receipts = try EscPosRasterDecoder.decode(payload)
        #expect(receipts.count == 1 && receipts[0].bitmap == bitmap && receipts[0].cut)
        #expect([UInt8](payload).contains(0x28), "the payload really does carry GS ( K settings")
    }

    @Test func decoderRejectsATruncatedSettingsCommand() {
        #expect(throws: EscPosDecodeError.self) { try EscPosRasterDecoder.decode(Data([0x1B, 0x40, 0x1D, 0x28, 0x4B, 0x02, 0x00, 0x31])) }
    }
}
