import CoreGraphics
import Foundation

/// A logo ready to print: the bitmap already includes the gap on the side that faces the receipt.
public struct PlacedLogo: Sendable {
    public let bitmap: MonoBitmap
    public let position: LogoPosition

    /// Stacks the logo above (`.top`) or below (`.bottom`) the receipt. Widths must match.
    public func applied(to receipt: MonoBitmap) -> MonoBitmap {
        switch position {
        case .top: bitmap.appending(receipt)
        case .bottom: receipt.appending(bitmap)
        }
    }
}

public enum LogoRenderer {
    /// The logo to print with every receipt, or nil when it is off, missing or unreadable.
    /// Failures are swallowed on purpose: a broken logo must never prevent a receipt from printing.
    public static func logo(model: PrinterModel, store: SettingsStore) -> PlacedLogo? {
        let settings = store.load().logo
        guard settings.enabled, let bitmap = previewBitmap(model: model, store: store) else { return nil }
        return place(bitmap, settings: settings)
    }

    /// The stored logo alone (no gap), even while it is switched off.
    public static func previewBitmap(model: PrinterModel, store: SettingsStore) -> MonoBitmap? {
        guard let image = try? ImageDecoder.load(url: store.logoURL) else { return nil }
        return try? RasterProcessor.process(image, model: model)
    }

    /// The stored logo with the configured gap on the receipt side, as it would print, even while the logo is off.
    /// Used by the settings app's preview.
    public static func previewImage(model: PrinterModel, store: SettingsStore) -> CGImage? {
        guard let bitmap = previewBitmap(model: model, store: store) else { return nil }
        return RasterProcessor.previewImage(place(bitmap, settings: store.load().logo).bitmap)
    }

    static func place(_ logo: MonoBitmap, settings: PrinterSettings.Logo) -> PlacedLogo {
        let gap = blank(width: logo.width, rows: max(0, min(settings.gapDots, SettingsStore.maxGapDots)))
        switch settings.position {
        case .top: return PlacedLogo(bitmap: logo.appending(gap), position: .top)
        case .bottom: return PlacedLogo(bitmap: gap.appending(logo), position: .bottom)
        }
    }

    static func blank(width: Int, rows: Int) -> MonoBitmap {
        MonoBitmap(width: width, height: rows, data: [UInt8](repeating: 0, count: MonoBitmap.rowBytes(forWidth: width) * rows))
    }
}

public extension MonoBitmap {
    /// Stacks `other` below this bitmap. Widths must match.
    func appending(_ other: MonoBitmap) -> MonoBitmap {
        precondition(width == other.width, "bitmaps must have the same width")
        return MonoBitmap(width: width, height: height + other.height, data: data + other.data)
    }
}
