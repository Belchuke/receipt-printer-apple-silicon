import Foundation
import Testing
@testable import ReceiptPrinterCore

final class RecordingReporter: FailureReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FailedJob] = []
    var failures: [FailedJob] { lock.withLock { items } }
    func report(_ failure: FailedJob) -> String? {
        lock.withLock { items.append(failure) }
        return "/tmp/recorded"
    }
}

struct FailingOutput: PrintOutput {
    var connectionName: String { "usb" }
    func send(_ payload: Data, jobID: Int) throws -> OutputReceipt {
        throw UsbError(.printerNotFound, "no USB device with vendor 0x04B8 and product name [\"TM-m30II\"] is connected")
    }
}

struct FailureLogTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_794_000_000)

    func makeLog(
        primary: FailureLog.Destination?,
        fallback: URL,
        model: PrinterModel = .tmM30II80mm,
        store: SettingsStore? = nil,
        usb: [SeenUsbDevice] = [SeenUsbDevice(productName: "TM-m30II", vendorID: 0x04B8, productID: 0x0E2A, mode: "Printer Class")],
        tail: [String] = ["{\"event\":\"job_received\",\"job_id\":3}"]
    ) -> FailureLog {
        FailureLog(
            model: model,
            store: store ?? SettingsStore(directory: SinkOutputTests.scratchDirectory()),
            primary: { primary },
            fallback: fallback,
            version: { "0.3.0" },
            usbDevices: { usb },
            logTail: { tail },
            now: { Self.fixedDate },
            system: { "Version 27.0 (Build TEST), Apple Silicon" }
        )
    }

    let failure = FailedJob(
        jobID: 3, format: "image/urf", bytes: 143_486,
        error: "output(\"printer_not_found: no USB device with vendor 0x04B8 is connected\")",
        requested: ["print-quality": "4", "document-format": "image/urf"], milliseconds: 19.6
    )

    @Test func reportGoesToTheChosenFolderAndHasTheFactsSupportNeeds() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(FailureLog.folderName)
        let log = makeLog(primary: .init(directory: folder, owner: nil), fallback: root.appendingPathComponent("fallback"))
        let path = try #require(log.report(failure))

        #expect(path.hasPrefix(folder.path))
        let text = try String(contentsOfFile: path, encoding: .utf8)
        for expected in [
            "print failure report", "Job number:       3", "printer_not_found", "image/urf, 143486 bytes",
            "document-format=image/urf, print-quality=4", "EPSON TM-m30II (576 dots, 203 dpi, 80 mm)",
            "Receipt Printer 0.3.0", "Version 27.0 (Build TEST), Apple Silicon", "TM-m30II (ID 04B8:0E2A, Printer Class)",
            "Recent service log", "\"job_id\":3", "no document content, job names or user names",
        ] {
            #expect(text.contains(expected), "missing: \(expected)")
        }
        let mode = try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        #expect(mode == 0o644)
    }

    @Test func reportNamesAreSortableAndCarryTheJobNumber() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = makeLog(primary: .init(directory: root.appendingPathComponent("logs"), owner: nil), fallback: root)
        let name = log.fileName(for: failure)
        #expect(name.hasPrefix("print-failure-") && name.hasSuffix("-job3.txt"))
        #expect(name.range(of: #"^print-failure-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-job3\.txt$"#, options: .regularExpression) != nil)
    }

    @Test func settingsAreSummarisedWithoutFilePaths() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(directory: root.appendingPathComponent("settings"))
        try store.save(PrinterSettings(model: "tm-m30iii", logo: .init(enabled: true, file: "logo.png", gapDots: 12, position: .top), density: 90))
        let log = makeLog(primary: nil, fallback: root.appendingPathComponent("fallback"), model: .tmM30III80mm, store: store)
        let text = log.render(failure)
        #expect(text.contains("model tm-m30iii; logo on, top, gap 12; density 90"))
        #expect(!text.contains(root.path), "no file system paths in a report that gets emailed")
        #expect(!text.contains("logo.png"))
    }

    @Test func fallsBackToTheSystemFolderWhenNoUserFolderIsAvailable() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fallback = root.appendingPathComponent("failures")
        let path = try #require(makeLog(primary: nil, fallback: fallback).report(failure))
        #expect(path.hasPrefix(fallback.path))
    }

    @Test func fallsBackWhenTheUserFolderCannotBeCreated() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let fallback = root.appendingPathComponent("failures")
        let log = makeLog(primary: .init(directory: blocker.appendingPathComponent("Receipt Printer Logs"), owner: nil), fallback: fallback)
        let path = try #require(log.report(failure))
        #expect(path.hasPrefix(fallback.path))
    }

    @Test func neverThrowsAndReturnsNilWhenNothingIsWritable() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let log = makeLog(primary: .init(directory: blocker.appendingPathComponent("a"), owner: nil), fallback: blocker.appendingPathComponent("b"))
        #expect(log.report(failure) == nil)
    }

    @Test func keepsOnlyTheNewestReportsAndLeavesOtherFilesAlone() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(FailureLog.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for day in 1...60 {
            let name = String(format: "print-failure-2020-01-%02d_10-00-00-job1.txt", day)
            try Data("old".utf8).write(to: folder.appendingPathComponent(name))
        }
        try Data("keep me".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let log = makeLog(primary: .init(directory: folder, owner: nil), fallback: root)
        _ = log.report(failure)

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let reports = names.filter { $0.hasPrefix(FailureLog.filePrefix) }
        #expect(reports.count == FailureLog.keepCount)
        #expect(names.contains("notes.txt"), "files that are not our reports are never deleted")
        #expect(!names.contains("print-failure-2020-01-01_10-00-00-job1.txt"), "the oldest went first")
        #expect(reports.contains { $0.contains("-job3") }, "the new report is kept")
    }

    @Test func tailReturnsTheLastLinesAndCopesWithMissingFiles() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("service.log")
        try (1...100).map { "line \($0)" }.joined(separator: "\n").data(using: .utf8)!.write(to: file)
        let tail = FailureLog.tail(of: file, count: 5)
        #expect(tail == ["line 96", "line 97", "line 98", "line 99", "line 100"])
        #expect(FailureLog.tail(of: root.appendingPathComponent("missing.log")).isEmpty)
    }

    @Test func consoleUserFolderIsInsideDocumentsWhenSomeoneIsLoggedIn() {
        if let destination = ConsoleUser.logsDestination() {
            #expect(destination.directory.lastPathComponent == "Receipt Printer Logs")
            #expect(destination.directory.deletingLastPathComponent().lastPathComponent == "Documents")
            #expect(destination.owner != nil)
        }
    }

    // MARK: The real job path

    func waitForJobs(_ jobs: JobManager) -> Bool {
        waitUntil { jobs.queuedCount == 0 && !jobs.isProcessing }
    }

    @Test func aFailedJobIsReportedAndASuccessfulOneIsNot() throws {
        let page = Fixture.urf(width: 570, height: 20) { _, _ in 0 }

        let failing = RecordingReporter()
        let failingJobs = JobManager(
            service: PrintService(model: .tmM30II80mm, output: FailingOutput()),
            log: ServiceLog(echoToStderr: false), failureReporter: failing
        )
        let job = failingJobs.submit(name: "secret invoice 4711", format: "image/urf", document: page, requested: ["print-quality": "4"])
        #expect(waitForJobs(failingJobs))
        let reported = try #require(failing.failures.first)
        #expect(failing.failures.count == 1)
        #expect(reported.jobID == job.id && reported.format == "image/urf" && reported.bytes == page.count)
        #expect(reported.error.contains("printer_not_found"))
        #expect(!"\(reported)".contains("secret invoice"), "the job name never reaches a report")

        let working = RecordingReporter()
        let out = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: out) }
        let workingJobs = JobManager(
            service: PrintService(model: .tmM30II80mm, output: SinkOutput(path: out.path)),
            log: ServiceLog(echoToStderr: false), failureReporter: working
        )
        _ = workingJobs.submit(name: "ok", format: "image/urf", document: page)
        #expect(waitForJobs(workingJobs))
        #expect(working.failures.isEmpty)
    }

    @Test func aGarbageDocumentIsReportedAsAFailure() throws {
        let reporter = RecordingReporter()
        let jobs = JobManager(
            service: PrintService(model: .tmM30II80mm, output: SinkOutput(path: SinkOutputTests.scratchDirectory().path)),
            log: ServiceLog(echoToStderr: false), failureReporter: reporter
        )
        _ = jobs.submit(name: "x", format: "application/octet-stream", document: Data("this is not a raster".utf8))
        #expect(waitForJobs(jobs))
        #expect(try #require(reporter.failures.first).error.contains("not URF or PWG raster"))
    }

    @Test func printingWorksWithNoReporterAtAll() {
        let out = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: out) }
        let jobs = JobManager(service: PrintService(model: .tmM30II80mm, output: FailingOutput()), log: ServiceLog(echoToStderr: false))
        _ = jobs.submit(name: "x", format: "image/urf", document: Fixture.urf(width: 570, height: 20) { _, _ in 0 })
        #expect(waitForJobs(jobs), "a failure with no reporter configured still ends the job normally")
    }
}

struct RejectedPrintReportTests {
    func handler(maxJobBytes: Int = 64 * 1024 * 1024, reporter: RecordingReporter?) -> IppRequestHandler {
        var config = IppServerConfig()
        config.maxJobBytes = maxJobBytes
        let jobs = JobManager(
            service: PrintService(model: .tmM30II80mm, output: SinkOutput(path: SinkOutputTests.scratchDirectory().path)),
            log: ServiceLog(echoToStderr: false)
        )
        return IppRequestHandler(config: config, jobs: jobs, log: ServiceLog(echoToStderr: false), failureReporter: reporter)
    }

    func submit(_ handler: IppRequestHandler, document: Data, format: String? = nil) throws -> IppMessage {
        var extra: [IppAttribute] = []
        if let format { extra.append(IppAttribute("document-format", .mimeMediaType(format))) }
        extra.append(IppAttribute("job-name", .name("private invoice 4711")))
        return try Fixture.decodeResponse(handler.handle(Fixture.ippRequest(IppOperation.printJob, extra: extra, document: document)))
    }

    @Test func aDocumentThePrinterCannotPrintIsReported() throws {
        let reporter = RecordingReporter()
        let response = try submit(handler(reporter: reporter), document: Data("not a raster".utf8), format: "application/octet-stream")
        #expect(response.code == IppStatus.documentFormatError)
        let failure = try #require(reporter.failures.first)
        #expect(reporter.failures.count == 1 && failure.jobID == 0)
        #expect(failure.error.contains("rejected") && failure.error.contains("not URF or PWG raster"))
        #expect(failure.format == "application/octet-stream" && failure.bytes == 12)
        #expect(!"\(failure)".contains("private invoice"), "the job name never reaches a report")
    }

    @Test func anUnsupportedDeclaredFormatIsReportedWithThatFormat() throws {
        let reporter = RecordingReporter()
        _ = try submit(handler(reporter: reporter), document: Data("%PDF-1.4".utf8), format: "application/pdf")
        let failure = try #require(reporter.failures.first)
        #expect(failure.format == "application/pdf" && failure.error.contains("document-format application/pdf not supported"))
    }

    @Test func anOversizedAndAnEmptyDocumentAreReported() throws {
        let reporter = RecordingReporter()
        let small = handler(maxJobBytes: 100, reporter: reporter)
        _ = try submit(small, document: Data(repeating: 1, count: 500))
        _ = try submit(small, document: Data())
        #expect(reporter.failures.count == 2)
        #expect(reporter.failures[0].error.contains("exceeds 100 bytes"))
        #expect(reporter.failures[1].error.contains("no document data"))
    }

    @Test func aGoodDocumentIsNotReported() throws {
        let reporter = RecordingReporter()
        let response = try submit(handler(reporter: reporter), document: Fixture.urf(width: 510, height: 20) { _, _ in 0 })
        #expect(response.code == IppStatus.ok)
        #expect(reporter.failures.isEmpty)
    }

    @Test func rejectedReportsHaveATellingFileNameAndText() throws {
        let root = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = FailureLog(model: .tmM30II80mm, store: SettingsStore(directory: root.appendingPathComponent("s")),
                             primary: { .init(directory: root.appendingPathComponent("logs"), owner: nil) }, fallback: root,
                             now: { Date(timeIntervalSince1970: 1_794_000_000) })
        let path = try #require(log.report(FailedJob(jobID: 0, format: "application/pdf", bytes: 8, error: "print request rejected: document-format application/pdf not supported")))
        #expect(path.hasSuffix("-rejected.txt"))
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("none (turned away before a job was created)"))
    }
}

struct PrinterCheckTests {
    func log(model: PrinterModel, devices: [SeenUsbDevice]) -> FailureLog {
        FailureLog(model: model, store: SettingsStore(directory: SinkOutputTests.scratchDirectory()),
                   primary: { nil }, fallback: SinkOutputTests.scratchDirectory(), usbDevices: { devices })
    }
    func device(_ name: String?, pid: UInt16 = 0x0E2A) -> SeenUsbDevice {
        SeenUsbDevice(productName: name, vendorID: 0x04B8, productID: pid, mode: "Printer Class")
    }
    let failure = FailedJob(jobID: 1, format: "image/urf", bytes: 10, error: "printer_not_found")

    @Test func rightPrinterIsConfirmed() {
        let text = log(model: .tmM30II80mm, devices: [device("TM-m30II")]).render(failure)
        #expect(text.contains("Printer check:    OK"))
        #expect(!text.contains("WRONG PRINTER MODEL"))
    }

    @Test func aWrongModelIsNamedWithTheFix() {
        // The set-up behind many "nothing prints" reports: the installer's default (TM-T88V) with another printer plugged in.
        let text = log(model: .tmT88V80mm, devices: [device("TM-m30II")]).render(failure)
        #expect(text.contains("WRONG PRINTER MODEL"))
        #expect(text.contains("set up for EPSON TM-T88V, but the connected printer is TM-m30II"))
        #expect(text.contains("supported EPSON TM-m30II"))
        #expect(text.contains("receipt-printer-config set-model tm-m30ii"))
        #expect(text.contains("then restart the service: sudo launchctl kickstart -k system/com.belchuke.receiptprinter.service"))
        #expect(text.contains("run the installer again and choose \"EPSON TM-m30II\""))
    }

    @Test func restartCommandNamesTheInstalledLaunchdJob() {
        #expect(FailureLog.restartCommand == "sudo launchctl kickstart -k system/com.belchuke.receiptprinter.service")
    }

    @Test func theTwoTM_T88ModelsAreNotConfused() {
        let text = log(model: .tmT88V80mm, devices: [device("TM-T88VII", pid: 0x0E2D)]).render(failure)
        #expect(text.contains("WRONG PRINTER MODEL") && text.contains("set-model tm-t88vii"))
        let reverse = log(model: .tmT88VII80mm, devices: [device("TM-T88V")]).render(failure)
        #expect(reverse.contains("set-model tm-t88v") && !reverse.contains("set-model tm-t88vii"))
        let threeIs = log(model: .tmM30II80mm, devices: [device("TM-m30III", pid: 0x0E32)]).render(failure)
        #expect(threeIs.contains("set-model tm-m30iii"))
    }

    @Test func noPrinterAtAllPointsAtCableAndPower() {
        let text = log(model: .tmM30II80mm, devices: []).render(failure)
        #expect(text.contains("PROBLEM - no Epson USB printer is visible"))
        #expect(text.contains("USB cable") && text.contains("power adapter"))
    }

    @Test func anUnknownEpsonDeviceIsFlaggedAsUnsupported() {
        let text = log(model: .tmM30II80mm, devices: [device("TM-X99")]).render(failure)
        #expect(text.contains("UNSUPPORTED PRINTER") && text.contains("TM-X99"))
        #expect(!text.contains("set-model"))
    }

    @Test func theRightPrinterWinsWhenSeveralAreConnected() {
        let text = log(model: .tmM30II80mm, devices: [device("TM-T88V"), device("TM-m30II")]).render(failure)
        #expect(text.contains("Printer check:    OK"))
    }

    @Test func noSerialNumberIsEverShown() {
        let text = log(model: .tmM30II80mm, devices: [device("TM-m30II")]).render(failure)
        #expect(!text.lowercased().contains("serial"))
        #expect(text.contains("TM-m30II (ID 04B8:0E2A, Printer Class)"))
    }
}

struct PrinterCheckClassificationTests {
    func device(_ name: String?) -> SeenUsbDevice { SeenUsbDevice(productName: name, vendorID: 0x04B8, productID: 1, mode: "Printer Class") }

    @Test func classifiesEachSituationWithAStableCode() {
        #expect(PrinterCheck.classify(model: .tmM30II80mm, devices: [device("TM-m30II")]) == [.matches])
        #expect(PrinterCheck.classify(model: .tmM30II80mm, devices: []) == [.noPrinter])
        #expect(PrinterCheck.classify(model: .tmT88V80mm, devices: [device("TM-m30II")]) == [.wrongModel(connected: "TM-m30II", shouldBe: "tm-m30ii")])
        #expect(PrinterCheck.classify(model: .tmT88V80mm, devices: [device("TM-X99")]) == [.unsupported(connected: "TM-X99")])
        #expect([PrinterCheck.matches, .noPrinter, .wrongModel(connected: "", shouldBe: ""), .unsupported(connected: "")].map(\.code)
                == ["ok", "no_printer", "wrong_model", "unsupported_printer"])
    }
}

struct LogTailFilterTests {
    @Test func routineStatusPollingIsDroppedButEverythingElseStays() {
        let poll = #"{"event":"ipp_request","operation":"Get-Printer-Attributes","request_bytes":769,"status":"0x0000","ts":"x"}"#
        let validate = #"{"event":"ipp_request","operation":"Validate-Job","request_bytes":261,"status":"0x0000","ts":"x"}"#
        let print = #"{"event":"ipp_request","operation":"Print-Job","request_bytes":2787,"status":"0x0000","ts":"x"}"#
        let refused = #"{"event":"ipp_request","operation":"Print-Job","request_bytes":255,"status":"0x0412","ts":"x"}"#
        let pollFailed = #"{"event":"ipp_request","operation":"Get-Printer-Attributes","request_bytes":9,"status":"0x0400","ts":"x"}"#
        for noise in [poll, validate] { #expect(!FailureLog.isUsefulLogLine(noise)) }
        for useful in [print, refused, pollFailed, #"{"event":"job_failed","job_id":1}"#, #"{"event":"printer_check","result":"wrong_model"}"#, #"{"event":"listening"}"#] {
            #expect(FailureLog.isUsefulLogLine(useful), "\(useful)")
        }
    }

    @Test func tailFiltersBeforeCountingAndShortensLongLines() throws {
        let dir = SinkOutputTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("service.log")
        var lines: [String] = []
        for i in 1...50 {
            lines.append(#"{"event":"ipp_request","operation":"Get-Printer-Attributes","status":"0x0000","n":\#(i)}"#)
            if i % 10 == 0 { lines.append(#"{"event":"job_failed","job_id":\#(i)}"#) }
        }
        lines.append(#"{"event":"job_completed","pad":"\#(String(repeating: "x", count: 600))"}"#)
        try lines.joined(separator: "\n").data(using: .utf8)!.write(to: file)

        let tail = FailureLog.tail(of: file, count: 4, include: FailureLog.isUsefulLogLine)
        #expect(tail.count == 4)
        #expect(tail.dropLast().allSatisfy { $0.contains("job_failed") }, "the noise did not use up the slots")
        #expect(tail.last?.hasSuffix("...") == true && (tail.last?.count ?? 0) <= 303)
    }
}
