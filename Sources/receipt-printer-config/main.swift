import Foundation
import ReceiptPrinterCore

setlinebuf(stdout)

let usage = """
usage: receipt-printer-config [--dir DIR] COMMAND

  show                  print the current settings
  set-logo IMAGE        use IMAGE (PNG or JPEG) as the receipt logo and turn it on
  enable-logo           print the stored logo on every receipt
  disable-logo          stop printing the logo (the image is kept)
  remove-logo           turn the logo off and delete the stored image
  set-position top|bottom  print the logo above (default) or below the receipt
  set-density N|default print darkness 0-127 (TM-T88VII); 0 is the printer standard, 127 the strongest
  set-gap DOTS          blank dots between the logo and the receipt (0-512, default 24)
  set-model NAME        printer model: \(PrinterModel.registryIDs.joined(separator: " | "))
  preview FILE          write the logo as it will print (1-bit PNG) to FILE

  --dir DIR             settings directory (default \(SettingsStore.defaultDirectory))
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

var directory = SettingsStore.defaultDirectory
var words: [String] = []
var remaining = Array(CommandLine.arguments.dropFirst())
while !remaining.isEmpty {
    let argument = remaining.removeFirst()
    switch argument {
    case "-h", "--help": print(usage); exit(0)
    case "--dir":
        guard !remaining.isEmpty else { fail("--dir requires a value\n\(usage)", code: 2) }
        directory = remaining.removeFirst()
    default: words.append(argument)
    }
}
guard let command = words.first else { fail(usage, code: 2) }

let store = SettingsStore(directory: URL(fileURLWithPath: directory))
var settings = store.load()
let model = settings.model.flatMap(PrinterModel.named) ?? .tmT88V80mm

@MainActor func argument(_ name: String) -> String {
    guard words.count == 2 else { fail("\(command) needs \(name)\n\(usage)", code: 2) }
    return words[1]
}

@MainActor func save() {
    do { try store.save(settings) } catch {
        fail("cannot write \(store.settingsURL.path): \(error)\nRun with sudo or as an administrator.")
    }
}

do {
    switch command {
    case "show":
        print("directory:  \(store.directory.path)")
        print("model:      \(settings.model ?? "default (tm-t88v)")")
        print("logo:       \(settings.logo.enabled ? "on" : "off")\(FileManager.default.fileExists(atPath: store.logoURL.path) ? "" : " (no image stored)")")
        print("logo place: \(settings.logo.position.rawValue) of the receipt")
        print("logo gap:   \(settings.logo.gapDots) dots")
        if model.supportsPrintDensity {
            let effective = store.effectivePrintDensity(for: model).map(String.init) ?? "printer standard"
            print("density:    \(effective)\(settings.density == nil ? " (default for \(model.name))" : "")")
        }
    case "set-logo":
        do { settings = try store.setLogo(from: URL(fileURLWithPath: argument("IMAGE")), model: model) } catch let error as RasterError { fail("\(error)") }
        print("logo set and enabled (\(settings.logo.position.rawValue) of the receipt) for \(model.name) (\(model.dotsPerLine) dots wide)")
    case "enable-logo":
        guard store.hasLogo else { fail("no logo stored; run set-logo IMAGE first") }
        settings = try store.setLogoEnabled(true)
        print("logo enabled")
    case "disable-logo":
        settings = try store.setLogoEnabled(false)
        print("logo disabled")
    case "remove-logo":
        settings = try store.removeLogo()
        print("logo removed")
    case "set-gap":
        guard let dots = Int(argument("DOTS")), (0...SettingsStore.maxGapDots).contains(dots) else { fail("DOTS must be 0-\(SettingsStore.maxGapDots)", code: 2) }
        settings = try store.setGap(dots)
        print("logo gap set to \(dots) dots")
    case "set-density":
        let text = argument("N|default").lowercased()
        guard model.supportsPrintDensity else { fail("\(model.name) is not set up for print density control", code: 2) }
        if text == "default" {
            settings = try store.setDensity(nil)
            print("print density reset to the default for \(model.name)")
        } else {
            guard let value = Int(text), (0...PrinterModel.maxPrintDensity).contains(value) else { fail("density must be 0-\(PrinterModel.maxPrintDensity) or default", code: 2) }
            settings = try store.setDensity(value)
            print("print density set to \(value); applies to the next print")
        }
    case "set-position":
        guard let position = LogoPosition(rawValue: argument("top|bottom").lowercased()) else { fail("position must be top or bottom", code: 2) }
        settings = try store.setPosition(position)
        print("logo will print at the \(position.rawValue) of the receipt")
    case "set-model":
        let name = argument("NAME").lowercased()
        guard PrinterModel.named(name) != nil else { fail("model must be one of: \(PrinterModel.registryIDs.joined(separator: ", "))", code: 2) }
        settings.model = name
        save()
        print("model set to \(name); restart the service for it to take effect")
    case "preview":
        let path = argument("FILE")
        guard let bitmap = LogoRenderer.previewBitmap(model: model, store: store), let image = RasterProcessor.previewImage(bitmap) else {
            fail("no readable logo stored in \(store.directory.path)")
        }
        try TestPattern.writePNG(image, to: URL(fileURLWithPath: path))
        print("wrote \(bitmap.width)x\(bitmap.height) preview to \(path)")
    default:
        fail("unknown command \(command)\n\(usage)", code: 2)
    }
} catch {
    fail("\(error)")
}
