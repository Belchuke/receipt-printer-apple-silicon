import CoreGraphics
import Foundation
import Testing
@testable import ReceiptPrinterCore

struct LogoTests {
    func makeStore() throws -> (SettingsStore, URL) {
        let dir = SinkOutputTests.scratchDirectory()
        let source = dir.appendingPathComponent("source.png")
        let pattern = try #require(TestPattern.make(width: 200))
        try TestPattern.writePNG(pattern, to: source)
        return (SettingsStore(directory: dir.appendingPathComponent("settings")), source)
    }

    func print(store: SettingsStore, model: PrinterModel = .tmT88V80mm) throws -> DecodedReceipt {
        let out = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: out) }
        var service = PrintService(model: model, output: SinkOutput(path: out.path))
        service.logo = { LogoRenderer.logo(model: model, store: store) }
        let page = Fixture.urf(width: 510, height: 400) { _, y in y < 30 ? 0 : 255 }
        _ = try service.print(document: page, declaredFormat: "image/urf", jobID: 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
        let receipts = try files.flatMap { try EscPosRasterDecoder.decode(Data(contentsOf: out.appendingPathComponent($0))) }
        return try #require(receipts.first)
    }

    @Test func logoAtTheBottomIsStackedUnderTheReceiptBeforeTheCut() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try store.installLogo(from: source, model: .tmT88V80mm)
        try store.save(PrinterSettings(logo: .init(enabled: true, file: SettingsStore.logoFileName, gapDots: 24, position: .bottom)))

        let logo = try #require(LogoRenderer.previewBitmap(model: .tmT88V80mm, store: store))
        let receipt = try print(store: store)
        #expect(receipt.bitmap.width == 512)
        #expect(receipt.bitmap.height == 30 + 24 + logo.height)
        #expect(receipt.cut)
        for y in 30..<54 { for x in stride(from: 0, to: 512, by: 37) { #expect(!receipt.bitmap.isBlack(x: x, y: y)) } }
    }

    @Test func disabledLogoLeavesTheReceiptUntouched() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try store.installLogo(from: source, model: .tmT88V80mm)
        try store.save(PrinterSettings(logo: .init(enabled: false, file: SettingsStore.logoFileName)))
        #expect(try print(store: store).bitmap.height == 30)
    }

    @Test func brokenOrMissingLogoNeverStopsPrinting() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try store.save(PrinterSettings(logo: .init(enabled: true, file: SettingsStore.logoFileName)))
        #expect(try print(store: store).bitmap.height == 30)
        try Data("not an image".utf8).write(to: store.logoURL)
        #expect(try print(store: store).bitmap.height == 30)
    }

    @Test func logoIsRenderedAtTheSelectedModelsWidth() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try store.installLogo(from: source, model: .tmM30II80mm)
        try store.save(PrinterSettings(logo: .init(enabled: true, file: SettingsStore.logoFileName)))
        let placed = try #require(LogoRenderer.logo(model: .tmM30II80mm, store: store))
        #expect(placed.bitmap.width == 576)
    }

    @Test func settingsRoundTripAndBadFileFallsBackToDefaults() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        #expect(store.load() == PrinterSettings())
        let saved = PrinterSettings(model: "tm-m30ii", logo: .init(enabled: true, file: "x.png", gapDots: 8, position: .bottom))
        try store.save(saved)
        #expect(store.load() == saved)
        try Data("{broken".utf8).write(to: store.settingsURL)
        #expect(store.load() == PrinterSettings())
    }

    @Test func savingTheModelKeepsTheInstallerMarkerInSync() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        func marker(_ id: String) -> Bool { FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("current-model.\(id)").path) }
        try store.save(PrinterSettings(model: "tm-m30ii"))
        #expect(marker("tm-m30ii") && !marker("tm-t88v"))
        try store.save(PrinterSettings(model: "tm-t88v"))
        #expect(marker("tm-t88v") && !marker("tm-m30ii"))
        try store.save(PrinterSettings())
        #expect(!marker("tm-t88v") && !marker("tm-m30ii"))
    }

    @Test func fileWrittenByTheInstallerWithOnlyAModelIsRead() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{\n  \"model\" : \"tm-m30ii\"\n}\n".utf8).write(to: store.settingsURL)
        #expect(store.load() == PrinterSettings(model: "tm-m30ii"))
        try Data("{\"bottomLogo\":{\"enabled\":true}}".utf8).write(to: store.settingsURL)
        #expect(store.load().logo == .init(enabled: true, file: nil, gapDots: 24))
        #expect(store.load().model == nil)
    }

    @Test func editsUsedBySettingsAppAndConfigToolWork() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        #expect(!store.hasLogo)
        #expect(try store.setLogoEnabled(true).logo.enabled == false, "cannot enable without an image")

        var settings = try store.setLogo(from: source, model: .tmM30II80mm)
        #expect(store.hasLogo && settings.logo.enabled && settings.logo.file == SettingsStore.logoFileName)

        settings = try store.setLogoEnabled(false)
        #expect(!settings.logo.enabled && store.hasLogo)
        #expect(try store.setLogoEnabled(true).logo.enabled)

        #expect(try store.setGap(40).logo.gapDots == 40)
        #expect(try store.setGap(-5).logo.gapDots == 0)
        #expect(try store.setGap(100_000).logo.gapDots == SettingsStore.maxGapDots)

        let preview = try #require(LogoRenderer.previewImage(model: .tmM30II80mm, store: store))
        let logo = try #require(LogoRenderer.previewBitmap(model: .tmM30II80mm, store: store))
        #expect(preview.width == 576 && preview.height == logo.height + SettingsStore.maxGapDots)

        settings = try store.removeLogo()
        #expect(!store.hasLogo && !settings.logo.enabled && settings.logo.file == nil)
        #expect(settings.logo.gapDots == SettingsStore.maxGapDots, "the gap survives removing the image")
        #expect(LogoRenderer.previewImage(model: .tmM30II80mm, store: store) == nil)
    }

    @Test func editsKeepTheModelAndRejectUnreadableImages() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try store.save(PrinterSettings(model: "tm-m30ii"))
        _ = try store.setLogo(from: source, model: .tmM30II80mm)
        #expect(store.load().model == "tm-m30ii")
        let bad = source.deletingLastPathComponent().appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        #expect(throws: (any Error).self) { try store.setLogo(from: bad, model: .tmM30II80mm) }
        #expect(store.load().logo.enabled, "a failed replace leaves the previous logo untouched")
    }

    @Test func logoDefaultsToTheTopOfTheReceipt() throws {
        #expect(PrinterSettings().logo.position == .top)
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try store.installLogo(from: source, model: .tmT88V80mm)
        try store.save(PrinterSettings(logo: .init(enabled: true, file: SettingsStore.logoFileName, gapDots: 24)))
        let logo = try #require(LogoRenderer.previewBitmap(model: .tmT88V80mm, store: store))

        let receipt = try print(store: store)
        #expect(receipt.bitmap.height == logo.height + 24 + 30)
        // The receipt (30 solid black rows) is now at the bottom; the 24 gap rows sit just above it.
        for y in (logo.height + 24)..<(logo.height + 54) { #expect(receipt.bitmap.isBlack(x: 100, y: y)) }
        for y in logo.height..<(logo.height + 24) { #expect(!receipt.bitmap.isBlack(x: 100, y: y)) }
    }

    @Test func logoAtTheBottomPutsTheReceiptFirst() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try store.installLogo(from: source, model: .tmT88V80mm)
        try store.save(PrinterSettings(logo: .init(enabled: true, file: SettingsStore.logoFileName, gapDots: 24, position: .bottom)))
        let receipt = try print(store: store)
        for y in 0..<30 { #expect(receipt.bitmap.isBlack(x: 100, y: y)) }
        for y in 30..<54 { #expect(!receipt.bitmap.isBlack(x: 100, y: y)) }
    }

    @Test func positionIsEditableAndSurvivesOtherEdits() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        _ = try store.setLogo(from: source, model: .tmT88V80mm)
        #expect(store.load().logo.position == .top)
        #expect(try store.setPosition(.bottom).logo.position == .bottom)
        _ = try store.setGap(8)
        _ = try store.setLogoEnabled(false)
        #expect(store.load().logo.position == .bottom)
        #expect(try store.removeLogo().logo.position == .bottom, "removing the image keeps the position")
    }

    @Test func previewPutsTheGapOnTheReceiptSide() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        _ = try store.setLogo(from: source, model: .tmT88V80mm)
        _ = try store.setGap(40)
        let logo = try #require(LogoRenderer.previewBitmap(model: .tmT88V80mm, store: store))
        #expect(try #require(LogoRenderer.logo(model: .tmT88V80mm, store: store)).position == .top)
        #expect(try #require(LogoRenderer.previewImage(model: .tmT88V80mm, store: store)).height == logo.height + 40)
        _ = try store.setPosition(.bottom)
        #expect(try #require(LogoRenderer.logo(model: .tmT88V80mm, store: store)).position == .bottom)
        #expect(try #require(LogoRenderer.previewImage(model: .tmT88V80mm, store: store)).height == logo.height + 40)
    }

    @Test func settingsFileUsesTheNewKeyAndStillReadsTheOldOne() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try store.save(PrinterSettings(model: "tm-m30ii", logo: .init(enabled: true, file: "logo.png", gapDots: 8, position: .bottom)))
        let text = try String(contentsOf: store.settingsURL, encoding: .utf8)
        #expect(text.contains("\"logo\"") && text.contains("\"position\" : \"bottom\"") && !text.contains("bottomLogo"))
        #expect(store.load().logo.position == .bottom)

        try Data("{\"model\":\"tm-m30ii\",\"bottomLogo\":{\"enabled\":true,\"gapDots\":8}}".utf8).write(to: store.settingsURL)
        let legacy = store.load()
        #expect(legacy.model == "tm-m30ii" && legacy.logo == .init(enabled: true, file: nil, gapDots: 8, position: .top))

        try Data("{\"logo\":{\"enabled\":true,\"position\":\"sideways\"}}".utf8).write(to: store.settingsURL)
        #expect(store.load().logo.position == .top, "an unknown position falls back to the top")
        #expect(store.load().logo.enabled)
    }

    @Test func aLogoStoredUnderTheOldFileNameIsStillUsedReplacedAndRemoved() throws {
        let (store, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let legacyURL = store.directory.appendingPathComponent(SettingsStore.legacyLogoFileName)
        try FileManager.default.copyItem(at: source, to: legacyURL)
        #expect(store.hasLogo && store.logoURL == legacyURL)
        #expect(LogoRenderer.previewBitmap(model: .tmT88V80mm, store: store) != nil)

        _ = try store.setLogo(from: source, model: .tmT88V80mm)
        #expect(store.logoURL.lastPathComponent == SettingsStore.logoFileName)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path), "replacing drops the old file")

        try FileManager.default.copyItem(at: source, to: legacyURL)
        _ = try store.removeLogo()
        #expect(!store.hasLogo && !FileManager.default.fileExists(atPath: legacyURL.path))
    }
}
