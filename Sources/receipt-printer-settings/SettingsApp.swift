import AppKit
import SwiftUI
import ReceiptPrinterCore

@main
struct ReceiptPrinterSettingsApp: App {
    @StateObject private var model = SettingsViewModel()

    var body: some Scene {
        // A single window: opening receiptprinter://settings (the printer's "Open Printer Utility" button) just brings it forward.
        Window("Receipt Printer Settings", id: "main") {
            ContentView(model: model)
                // The installer starts the app on behalf of the logged-in user, which does not raise it above other windows.
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
                .onOpenURL { _ in
                    model.reload()
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
    }
}
