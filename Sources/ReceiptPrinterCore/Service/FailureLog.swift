import Foundation

/// What went wrong with one print job. Deliberately small: no document content, job name or user name.
public struct FailedJob: Sendable {
    public let jobID: Int
    public let format: String
    public let bytes: Int
    public let error: String
    public let requested: [String: String]
    public let milliseconds: Double

    public init(jobID: Int, format: String, bytes: Int, error: String, requested: [String: String] = [:], milliseconds: Double = 0) {
        self.jobID = jobID
        self.format = format
        self.bytes = bytes
        self.error = error
        self.requested = requested
        self.milliseconds = milliseconds
    }
}

/// An Epson USB device the Mac can see. No serial number: a report is meant to be emailed.
public struct SeenUsbDevice: Sendable, Equatable {
    public let productName: String?
    public let vendorID: UInt16
    public let productID: UInt16
    public let mode: String

    public init(productName: String?, vendorID: UInt16, productID: UInt16, mode: String) {
        self.productName = productName
        self.vendorID = vendorID
        self.productID = productID
        self.mode = mode
    }

    public var summary: String {
        "\(productName ?? "unnamed device") (ID \(String(format: "%04X:%04X", vendorID, productID)), \(mode))"
    }
}

/// Whether the Epson printer that is plugged in is the one a service is set up for.
public enum PrinterCheck: Equatable, Sendable {
    case matches
    /// Nothing from Epson is visible: cable, power switch or adapter.
    case noPrinter
    /// A supported printer of another model is connected: the commonest cause of "nothing prints".
    case wrongModel(connected: String, shouldBe: String)
    /// An Epson device this software does not know.
    case unsupported(connected: String)

    public static func classify(model: PrinterModel, devices: [SeenUsbDevice]) -> [PrinterCheck] {
        if devices.contains(where: { model.matches(productName: $0.productName) }) { return [.matches] }
        guard !devices.isEmpty else { return [.noPrinter] }
        return devices.map { device in
            let name = device.productName ?? "an unnamed Epson device"
            if let known = PrinterModel.registry.first(where: { $0.model.matches(productName: device.productName) }) {
                return .wrongModel(connected: name, shouldBe: known.id)
            }
            return .unsupported(connected: name)
        }
    }

    /// Short machine-readable code for the service log.
    public var code: String {
        switch self {
        case .matches: "ok"
        case .noPrinter: "no_printer"
        case .wrongModel: "wrong_model"
        case .unsupported: "unsupported_printer"
        }
    }
}

public protocol FailureReporting: Sendable {
    /// Records a failed job. Never throws and never blocks printing. Returns where the report was saved, or nil.
    @discardableResult func report(_ failure: FailedJob) -> String?
}

/// Writes a plain-text report for every failed print job into the logged-in user's
/// `Documents/Receipt Printer Logs` folder, so a customer can send it to support.
public struct FailureLog: FailureReporting {
    public static let folderName = "Receipt Printer Logs"
    public static let filePrefix = "print-failure-"
    public static let keepCount = 50
    /// Kept in step with SERVICE_LABEL in scripts/config.sh (the bundle prefix plus ".service").
    public static let restartCommand = "sudo launchctl kickstart -k system/com.belchuke.receiptprinter.service"

    public struct Destination: Sendable {
        public let directory: URL
        /// Owner for the folder and files. The service runs as root, so without this the user could not delete them.
        public let owner: (uid: uid_t, gid: gid_t)?

        public init(directory: URL, owner: (uid: uid_t, gid: gid_t)?) {
            self.directory = directory
            self.owner = owner
        }
    }

    public let model: PrinterModel
    public let store: SettingsStore
    public let primary: @Sendable () -> Destination?
    public let fallback: URL
    public let version: @Sendable () -> String
    public let usbDevices: @Sendable () -> [SeenUsbDevice]
    public let logTail: @Sendable () -> [String]
    public let now: @Sendable () -> Date
    public let system: @Sendable () -> String

    public init(
        model: PrinterModel,
        store: SettingsStore,
        primary: @escaping @Sendable () -> Destination? = { ConsoleUser.logsDestination() },
        fallback: URL,
        version: @escaping @Sendable () -> String = { "unknown" },
        usbDevices: @escaping @Sendable () -> [SeenUsbDevice] = { [] },
        logTail: @escaping @Sendable () -> [String] = { [] },
        now: @escaping @Sendable () -> Date = { Date() },
        system: @escaping @Sendable () -> String = { FailureLog.systemDescription() }
    ) {
        self.model = model
        self.store = store
        self.primary = primary
        self.fallback = fallback
        self.version = version
        self.usbDevices = usbDevices
        self.logTail = logTail
        self.now = now
        self.system = system
    }

    @discardableResult
    public func report(_ failure: FailedJob) -> String? {
        let text = render(failure)
        let name = fileName(for: failure)
        if let destination = primary(), let url = try? write(text, named: name, to: destination) {
            return url.path
        }
        // Documents not writable (no logged-in user, or macOS privacy protection): keep the report in the system log folder.
        if let url = try? write(text, named: name, to: Destination(directory: fallback, owner: nil)) {
            return url.path
        }
        return nil
    }

    // MARK: Writing

    func write(_ text: String, named name: String, to destination: Destination) throws -> URL {
        let fm = FileManager.default
        let directory = destination.directory
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
            if let owner = destination.owner { chown(directory.path, owner.uid, owner.gid) }
        }
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        if let owner = destination.owner { chown(url.path, owner.uid, owner.gid) }
        prune(directory)
        return url
    }

    /// Keeps the newest `keepCount` reports so a printer that fails all day cannot fill the disk.
    func prune(_ directory: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let reports = names.filter { $0.hasPrefix(Self.filePrefix) && $0.hasSuffix(".txt") }.sorted()
        for old in reports.dropLast(Self.keepCount) {
            try? fm.removeItem(at: directory.appendingPathComponent(old))
        }
    }

    func fileName(for failure: FailedJob) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let suffix = failure.jobID == 0 ? "rejected" : "job\(failure.jobID)"
        return "\(Self.filePrefix)\(formatter.string(from: now()))-\(suffix).txt"
    }

    // MARK: Contents

    func render(_ failure: FailedJob) -> String {
        let stamp = ISO8601DateFormatter()
        stamp.timeZone = .current
        let settings = store.load()
        var lines: [String] = []
        lines.append("Receipt Printer - print failure report")
        lines.append(String(repeating: "=", count: 40))
        lines.append("Time:             \(stamp.string(from: now()))")
        lines.append("Job number:       \(failure.jobID == 0 ? "none (turned away before a job was created)" : String(failure.jobID))")
        lines.append("What went wrong:  \(failure.error)")
        lines.append("Document:         \(failure.format), \(failure.bytes) bytes, handled in \(Int(failure.milliseconds)) ms")
        if !failure.requested.isEmpty {
            lines.append("Requested:        " + failure.requested.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        }
        lines.append("")
        lines.append("Printer model:    \(model.name) (\(model.dotsPerLine) dots, \(model.dpi) dpi, \(Int(model.paperWidthMM)) mm)")
        lines.append("Settings:         model \(settings.model ?? "default"); logo \(settings.logo.enabled ? "on, \(settings.logo.position.rawValue), gap \(settings.logo.gapDots)" : "off"); density \(settings.density.map(String.init) ?? "default")")
        lines.append("Software:         Receipt Printer \(version())")
        lines.append("macOS:            \(system())")
        lines.append("")
        lines.append("Epson USB devices seen right now:")
        let devices = usbDevices()
        lines.append(contentsOf: devices.isEmpty ? ["  (none found)"] : devices.map { "  - \($0.summary)" })
        lines.append("")
        lines.append(contentsOf: printerCheck(devices))
        let tail = logTail()
        if !tail.isEmpty {
            lines.append("")
            lines.append("Recent service log (newest last):")
            lines.append(contentsOf: tail.map { "  \($0)" })
        }
        lines.append("")
        lines.append("This report contains no document content, job names or user names.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Says whether the printer that is plugged in is the one the service is set up for, because the commonest cause of
    /// "nothing prints" is the wrong model chosen in the installer (for example a TM-T88V profile with a TM-T88VII).
    func printerCheck(_ devices: [SeenUsbDevice]) -> [String] {
        var lines: [String] = []
        for check in PrinterCheck.classify(model: model, devices: devices) {
            switch check {
            case .matches:
                lines.append("Printer check:    OK - the connected printer matches the model this service is set up for (\(model.name)).")
            case .noPrinter:
                lines.append("Printer check:    PROBLEM - no Epson USB printer is visible to this Mac.")
                lines.append("                  Check the USB cable, that the printer is switched on, and its power adapter.")
            case .wrongModel(let connected, let shouldBe):
                let known = PrinterModel.named(shouldBe)?.name ?? shouldBe
                lines.append("Printer check:    WRONG PRINTER MODEL - this service is set up for \(model.name), but the connected printer is \(connected),")
                lines.append("                  which is a supported \(known). Easiest fix: run the installer again and choose \"\(known)\".")
                lines.append("                  Or in Terminal: receipt-printer-config set-model \(shouldBe)")
                lines.append("                  then restart the service: \(Self.restartCommand)")
            case .unsupported(let connected):
                lines.append("Printer check:    UNSUPPORTED PRINTER - this service is set up for \(model.name), and the connected Epson device")
                lines.append("                  \(connected) is not a model this software supports yet. Please send this report to support.")
            }
        }
        return lines
    }

    public static func systemDescription() -> String {
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        return "\(ProcessInfo.processInfo.operatingSystemVersionString), \(arch)"
    }

    /// Routine status polling (a Mac asks the printer for its attributes every few seconds) would bury the useful lines.
    /// Keeps everything except successful IPP requests that are not a print request.
    public static func isUsefulLogLine(_ line: String) -> Bool {
        guard line.contains("\"event\":\"ipp_request\"") else { return true }
        return line.contains("\"operation\":\"Print-Job\"") || !line.contains("\"status\":\"0x0000\"")
    }

    /// The last `count` lines of a text file (for the recent-log section); empty when it cannot be read.
    /// Lines are shortened to 300 characters, and `include` can drop noise before the last `count` are chosen.
    public static func tail(of url: URL, count: Int = 40, maxBytes: Int = 256 * 1024, include: (String) -> Bool = { _ in true }) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.filter(include).suffix(count).map { $0.count > 300 ? String($0.prefix(300)) + "..." : $0 }
    }
}

public enum ConsoleUser {
    /// `~/Documents/Receipt Printer Logs` of whoever is logged in at the screen, or nil when nobody is
    /// (or only root). The service runs as root, so the folder is created with that user as the owner.
    public static func logsDestination() -> FailureLog.Destination? {
        var info = stat()
        guard stat("/dev/console", &info) == 0, info.st_uid != 0, let entry = getpwuid(info.st_uid) else { return nil }
        let home = URL(fileURLWithPath: String(cString: entry.pointee.pw_dir))
        let documents = home.appendingPathComponent("Documents")
        guard FileManager.default.fileExists(atPath: documents.path) else { return nil }
        return FailureLog.Destination(
            directory: documents.appendingPathComponent(FailureLog.folderName),
            owner: (info.st_uid, info.st_gid)
        )
    }
}
