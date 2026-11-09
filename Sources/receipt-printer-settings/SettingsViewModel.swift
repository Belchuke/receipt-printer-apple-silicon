import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ReceiptPrinterCore

@MainActor
final class SettingsViewModel: ObservableObject {
    let store: SettingsStore

    @Published private(set) var settings = PrinterSettings()
    @Published private(set) var printer: PrinterModel = .tmT88V80mm
    @Published private(set) var preview: NSImage?
    @Published private(set) var canWrite = true
    @Published var gapDots = 24.0
    /// Print darkness on the slider (0 = printer standard ... 127 = strongest); only meaningful when `supportsDensity`.
    @Published var density = 0.0
    @Published var message: String?

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        reload()
    }

    var supportsDensity: Bool { printer.supportsPrintDensity }
    var densityIsDefault: Bool { settings.density == nil }
    var hasLogo: Bool { store.hasLogo }
    var logoEnabled: Bool { settings.logo.enabled }
    var position: LogoPosition { settings.logo.position }

    /// The gap in millimetres at the printer's resolution, for display next to the slider.
    var gapMillimetres: Double { gapDots / Double(printer.dpi) * 25.4 }

    func reload() {
        settings = store.load()
        printer = settings.model.flatMap(PrinterModel.named) ?? .tmT88V80mm
        gapDots = Double(settings.logo.gapDots)
        density = Double(printer.effectivePrintDensity(userChoice: settings.density) ?? 0)
        canWrite = FileManager.default.isWritableFile(atPath: store.directory.path)
        refreshPreview()
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a logo"
        panel.message = "The image is printed on every receipt."
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply { try $0.setLogo(from: url, model: self.printer) }
    }

    func setEnabled(_ enabled: Bool) {
        apply { try $0.setLogoEnabled(enabled) }
    }

    func removeLogo() {
        apply { try $0.removeLogo() }
    }

    func setPosition(_ position: LogoPosition) {
        guard position != settings.logo.position else { return }
        apply { try $0.setPosition(position) }
    }

    func commitDensity() {
        let value = Int(density.rounded())
        guard value != Int(printer.effectivePrintDensity(userChoice: settings.density) ?? 0) else { return }
        apply { try $0.setDensity(value) }
    }

    func resetDensity() {
        apply { try $0.setDensity(nil) }
    }

    func commitGap() {
        let dots = Int(gapDots.rounded())
        guard dots != settings.logo.gapDots else { return }
        apply { try $0.setGap(dots) }
    }

    private func apply(_ edit: (SettingsStore) throws -> PrinterSettings) {
        message = nil
        do {
            settings = try edit(store)
            gapDots = Double(settings.logo.gapDots)
            density = Double(printer.effectivePrintDensity(userChoice: settings.density) ?? 0)
        } catch let error as RasterError {
            message = "That image can't be used: \(error)"
        } catch {
            message = canWrite
                ? "Could not save the settings: \(error.localizedDescription)"
                : "Only an administrator can change these settings."
        }
        canWrite = FileManager.default.isWritableFile(atPath: store.directory.path)
        refreshPreview()
    }

    private func refreshPreview() {
        guard let image = LogoRenderer.previewImage(model: printer, store: store) else {
            preview = nil
            return
        }
        preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
