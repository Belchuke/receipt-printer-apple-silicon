import Foundation

public enum UpdaterConstants {
    public static let packageIdentifier = "com.belchuke.receiptprinter.pkg"
    /// The installer ships one tiny component per printer model so the customize screen can offer a choice.
    /// Only these exact identifiers are accepted next to the main package. Keep in sync with MODEL_IDS in scripts/config.sh.
    public static let modelPackageIdentifierPrefix = "com.belchuke.receiptprinter.model."
    public static let knownModelIDs = ["tm-t88v", "tm-t88vii", "tm-m30ii"]
    public static var allowedModelPackageIdentifiers: Set<String> { Set(knownModelIDs.map { modelPackageIdentifierPrefix + $0 }) }
    public static let requiredTeamID = "P3WL6DBK59"
    public static let officialUpdateURL = URL(string: "https://github.com/Belchuke/receipt-printer-apple-silicon/releases/latest/download/ReceiptPrinter.pkg")!

    public static let maxDownloadBytes: Int64 = 100 * 1024 * 1024
    public static let connectTimeoutSeconds = 20
    public static let downloadTimeoutSeconds = 300
    public static let installerTimeoutSeconds: TimeInterval = 900
    public static let commandTimeoutSeconds: TimeInterval = 120

    public static let minimumIntervalSeconds = 24 * 60 * 60
    public static let maximumJitterSeconds = 6 * 60 * 60

    public static let notarizedGatekeeperSource = "Notarized Developer ID"
    public static let leafCertificatePrefix = "Developer ID Installer: "
    public static let intermediateCertificateName = "Developer ID Certification Authority"
    public static let rootCertificateName = "Apple Root CA"
}

public struct UpdaterPaths: Sendable {
    public let supportDir: String
    public let logDir: String

    public init(root: String = "") {
        supportDir = root + "/Library/Application Support/ReceiptPrinter"
        logDir = root + "/Library/Logs/ReceiptPrinter"
    }

    public var stateDir: String { supportDir + "/state" }
    public var configPath: String { supportDir + "/config.json" }
    public var statePath: String { stateDir + "/updater-state.json" }
    public var lockPath: String { stateDir + "/updater.lock" }
    public var updateInProgressPath: String { stateDir + "/update-in-progress" }
    public var logPath: String { logDir + "/updater.log" }
}
