import Foundation

public enum LogoPosition: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
}

/// User-editable printer settings, stored as `printer.json` next to the installed service.
/// The installer writes `model`; the config tool and the settings app edit the logo.
public struct PrinterSettings: Codable, Equatable, Sendable {
    public struct Logo: Codable, Equatable, Sendable {
        public var enabled = false
        /// File name inside the settings directory (never a path).
        public var file: String?
        /// Blank dots between the logo and the receipt.
        public var gapDots = 24
        /// Where the logo is printed relative to the receipt. Defaults to the top.
        public var position = LogoPosition.top

        public init(enabled: Bool = false, file: String? = nil, gapDots: Int = 24, position: LogoPosition = .top) {
            self.enabled = enabled
            self.file = file
            self.gapDots = gapDots
            self.position = position
        }

        /// Every key is optional on disk: older files lack newer keys, and an unknown position falls back to the top.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            file = try container.decodeIfPresent(String.self, forKey: .file)
            gapDots = try container.decodeIfPresent(Int.self, forKey: .gapDots) ?? 24
            position = (try? container.decodeIfPresent(LogoPosition.self, forKey: .position)) ?? .top
        }
    }

    /// Registry id such as "tm-m30ii"; nil keeps the built-in default.
    public var model: String?
    public var logo = Logo()
    /// Print density chosen by the user (0...127); nil uses the model's default. Only sent to printers that support it.
    public var density: Int?

    public init(model: String? = nil, logo: Logo = Logo(), density: Int? = nil) {
        self.model = model
        self.logo = logo
        self.density = density
    }

    private enum CodingKeys: String, CodingKey {
        case model, logo, density
        /// The key used before the logo could go at the top. Read for compatibility, never written.
        case legacyBottomLogo = "bottomLogo"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        density = try? container.decodeIfPresent(Int.self, forKey: .density)
        logo = try container.decodeIfPresent(Logo.self, forKey: .logo)
            ?? container.decodeIfPresent(Logo.self, forKey: .legacyBottomLogo)
            ?? Logo()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(logo, forKey: .logo)
        try container.encodeIfPresent(density, forKey: .density)
    }
}

public struct SettingsStore: Sendable {
    public static let defaultDirectory = "/Library/Application Support/ReceiptPrinter"
    public static let logoFileName = "logo.png"
    /// Name used before the logo could go at the top; still found, replaced and removed correctly.
    public static let legacyLogoFileName = "bottom-logo.png"
    public static let maxGapDots = 512

    public let directory: URL

    public init(directory: URL = URL(fileURLWithPath: SettingsStore.defaultDirectory)) {
        self.directory = directory
    }

    public var settingsURL: URL { directory.appendingPathComponent("printer.json") }

    public var logoURL: URL {
        let current = directory.appendingPathComponent(Self.logoFileName)
        let legacy = directory.appendingPathComponent(Self.legacyLogoFileName)
        let fm = FileManager.default
        return !fm.fileExists(atPath: current.path) && fm.fileExists(atPath: legacy.path) ? legacy : current
    }

    public var hasLogo: Bool { FileManager.default.fileExists(atPath: logoURL.path) }

    /// Missing or unreadable settings fall back to defaults so a bad file can never stop printing.
    public func load() -> PrinterSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(PrinterSettings.self, from: data) else { return PrinterSettings() }
        return settings
    }

    public func save(_ settings: PrinterSettings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
        syncModelMarker(settings.model)
    }

    /// `current-model.<id>` mirrors the stored model so the installer's choice screen can preselect it (its scripting can only
    /// test whether a file exists). Best effort: a missing marker only changes which printer the screen preselects.
    private func syncModelMarker(_ model: String?) {
        let fm = FileManager.default
        for id in PrinterModel.registryIDs { try? fm.removeItem(at: directory.appendingPathComponent("current-model.\(id)")) }
        if let model, PrinterModel.named(model) != nil {
            fm.createFile(atPath: directory.appendingPathComponent("current-model.\(model.lowercased())").path, contents: Data())
        }
    }

    /// Validates `source` against `model`, then stores it as a normalized PNG so later edits to the original do not matter.
    public func installLogo(from source: URL, model: PrinterModel) throws {
        let image = try ImageDecoder.load(url: source)
        _ = try RasterProcessor.process(image, model: model)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TestPattern.writePNG(image, to: directory.appendingPathComponent(Self.logoFileName))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(Self.legacyLogoFileName))
    }

    // MARK: High-level edits shared by the config tool and the settings app

    /// Stores `source` as the logo and turns it on. The position and gap are kept.
    @discardableResult
    public func setLogo(from source: URL, model: PrinterModel) throws -> PrinterSettings {
        try installLogo(from: source, model: model)
        var settings = load()
        settings.logo.enabled = true
        settings.logo.file = Self.logoFileName
        try save(settings)
        return settings
    }

    @discardableResult
    public func setLogoEnabled(_ enabled: Bool) throws -> PrinterSettings {
        var settings = load()
        settings.logo.enabled = enabled && hasLogo
        try save(settings)
        return settings
    }

    /// Turns the logo off and deletes the stored image; the position and gap are kept.
    @discardableResult
    public func removeLogo() throws -> PrinterSettings {
        var settings = load()
        settings.logo = PrinterSettings.Logo(gapDots: settings.logo.gapDots, position: settings.logo.position)
        for name in [Self.logoFileName, Self.legacyLogoFileName] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        try save(settings)
        return settings
    }

    @discardableResult
    public func setGap(_ dots: Int) throws -> PrinterSettings {
        var settings = load()
        settings.logo.gapDots = max(0, min(dots, Self.maxGapDots))
        try save(settings)
        return settings
    }

    /// Sets the print density (clamped to 0...127), or nil to go back to the model's default.
    @discardableResult
    public func setDensity(_ value: Int?) throws -> PrinterSettings {
        var settings = load()
        settings.density = value.map { max(0, min($0, PrinterModel.maxPrintDensity)) }
        try save(settings)
        return settings
    }

    /// What the service sends for `model` right now.
    public func effectivePrintDensity(for model: PrinterModel) -> UInt8? {
        model.effectivePrintDensity(userChoice: load().density)
    }

    @discardableResult
    public func setPosition(_ position: LogoPosition) throws -> PrinterSettings {
        var settings = load()
        settings.logo.position = position
        try save(settings)
        return settings
    }
}
