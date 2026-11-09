import Foundation
import ReceiptPrinterCore

setlinebuf(stdout)

let usage = """
usage: receipt-printer-service [options]

  --port N          loopback TCP port (default 8632; 0 picks a free port)
  --sink PATH       write ESC/POS to PATH instead of USB (a directory gets job-N.escpos); never touches the printer
  --model NAME      printer model: tm-t88v (default) | tm-t88vii | tm-m30ii
  --paper 80|58     paper width preset, TM-T88V only (default 80)
  --name NAME       printer name advertised over IPP (default "Epson Receipt Printer")
  --serial SERIAL   use the printer with this USB serial
  --log-file PATH   also write JSON-line logs to PATH (rotated at 1 MB, 3 files kept)
  --quiet           do not echo log lines to stderr (use with --log-file when run by launchd)
  --settings-dir D  directory holding printer.json and the logo (default /Library/Application Support/ReceiptPrinter)
  --max-job-mb N    reject documents larger than N MB (default 64)

Listens on 127.0.0.1 and ::1 only. No Bonjour/DNS-SD advertisement.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

var config = IppServerConfig()
var sinkPath: String?
var serial: String?
var logPath: String?
var quiet = false
var settingsDir: String?
var modelFromFlag = false

var remaining = Array(CommandLine.arguments.dropFirst())
while !remaining.isEmpty {
    let argument = remaining.removeFirst()
    func value() -> String {
        guard !remaining.isEmpty else { fail("\(argument) requires a value\n\(usage)") }
        return remaining.removeFirst()
    }
    switch argument {
    case "-h", "--help":
        print(usage)
        exit(0)
    case "--port":
        guard let port = UInt16(value()) else { fail("invalid port") }
        config.port = port
    case "--sink": sinkPath = value()
    case "--paper":
        modelFromFlag = true
        switch value() {
        case "80": config.model = .tmT88V80mm
        case "58": config.model = .tmT88V58mm
        case let other: fail("unsupported paper width \(other)")
        }
    case "--name": config.printerName = value()
    case "--model":
        guard let selected = PrinterModel.named(value()) else { fail("--model must be one of: \(PrinterModel.registryIDs.joined(separator: ", "))") }
        config.model = selected
        modelFromFlag = true
    case "--settings-dir": settingsDir = value()
    case "--serial": serial = value()
    case "--log-file": logPath = value()
    case "--quiet": quiet = true
    case "--max-job-mb":
        guard let mb = Int(value()), mb > 0, mb <= 512 else { fail("--max-job-mb must be 1-512") }
        config.maxJobBytes = mb * 1024 * 1024
    default: fail("unknown argument \(argument)\n\(usage)")
    }
}

let store = settingsDir.map { SettingsStore(directory: URL(fileURLWithPath: $0)) } ?? SettingsStore()
if !modelFromFlag, let id = store.load().model, let selected = PrinterModel.named(id) { config.model = selected }

let log = ServiceLog(fileURL: logPath.map { URL(fileURLWithPath: $0) }, echoToStderr: !quiet)
let output: PrintOutput = sinkPath.map { SinkOutput(path: $0) } ?? UsbOutput(model: config.model, serial: serial)
var printService = PrintService(model: config.model, output: output)
let activeModel = config.model
printService.logo = { LogoRenderer.logo(model: activeModel, store: store) }
printService.density = { store.effectivePrintDensity(for: activeModel) }
let jobs = JobManager(service: printService, log: log)
let server = IppHTTPServer(config: config, handler: IppRequestHandler(config: config, jobs: jobs, log: log), log: log)

do {
    try server.start()
} catch {
    log.event("start_failed", ["error": "\(error)"])
    exit(1)
}

config.port = server.port
log.event("listening", [
    "addresses": server.boundAddresses,
    "printer_uri": config.printerURI(),
    "output": output.connectionName,
    "sink": sinkPath ?? "",
    "paper": config.model.name,
    "dots": config.model.dotsPerLine,
    "bonjour": false,
])
print("printer-uri: \(config.printerURI())")

let signalSources = [SIGINT, SIGTERM].map { signalNumber -> DispatchSourceSignal in
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        log.event("stopping", ["signal": signalNumber])
        server.stop()
        exit(0)
    }
    source.resume()
    return source
}
withExtendedLifetime(signalSources) { dispatchMain() }

