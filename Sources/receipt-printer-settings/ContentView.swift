import AppKit
import SwiftUI
import ReceiptPrinterCore

struct ContentView: View {
    @ObservedObject var model: SettingsViewModel

    private let controlsWidth: CGFloat = 330

    var body: some View {
        // Controls on the left, preview on the right. The preview scales to fit the space it has, so the whole picture is
        // always visible and the window never needs to scroll.
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                controls
                    .padding(24)
                    .frame(width: controlsWidth, alignment: .leading)
            }
            .frame(width: controlsWidth)

            Divider()

            previewPane
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 560, idealHeight: 640)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            printerSection
            if model.supportsDensity {
                Divider()
                densitySection
            }
            Divider()
            logoSection
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.canWrite {
                Label("Only an administrator can change these settings.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var printerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Printer").font(.headline)
            Text(model.printer.name)
            Text("\(Int(model.printer.paperWidthMM)) mm paper, \(model.printer.dotsPerLine) dots wide, \(model.printer.dpi) dpi. To use a different printer, run the installer again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var densitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Print darkness").font(.headline)
            Text("How strongly the printer heats the paper. Raise it if small text looks pale. It applies to the next print.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Slider(value: $model.density, in: 0...Double(PrinterModel.maxPrintDensity), step: 1) { editing in
                if !editing { model.commitDensity() }
            }
            .disabled(!model.canWrite)
            HStack {
                Text(model.density < 1 ? "Printer standard" : "\(Int(model.density.rounded())) of \(PrinterModel.maxPrintDensity)")
                    .monospacedDigit()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use default") { model.resetDensity() }
                    .controlSize(.small)
                    .disabled(model.densityIsDefault || !model.canWrite)
            }
        }
    }

    private var logoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logo").font(.headline)
            Text("Printed on every receipt, at the top or the bottom.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Print the logo on every receipt", isOn: Binding(get: { model.logoEnabled }, set: model.setEnabled))
                .disabled(!model.hasLogo || !model.canWrite)

            HStack {
                Button(model.hasLogo ? "Replace Image…" : "Choose Image…") { model.chooseImage() }
                Button("Remove", role: .destructive) { model.removeLogo() }
                    .disabled(!model.hasLogo)
            }
            .disabled(!model.canWrite)

            VStack(alignment: .leading, spacing: 4) {
                Text("Position")
                Picker("Position", selection: Binding(get: { model.position }, set: model.setPosition)) {
                    Text("Top").tag(LogoPosition.top)
                    Text("Bottom").tag(LogoPosition.bottom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!model.hasLogo || !model.canWrite)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Space between the logo and the receipt")
                Slider(value: $model.gapDots, in: 0...120, step: 4) { editing in
                    if !editing { model.commitGap() }
                }
                .disabled(!model.hasLogo || !model.canWrite)
                Text("\(Int(model.gapDots.rounded())) dots (\(String(format: "%.1f", model.gapMillimetres)) mm)")
                    .monospacedDigit()
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Preview

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                if model.preview != nil, model.position == .bottom { receiptPlaceholder }
                if let preview = model.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("No logo selected")
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if model.preview != nil, model.position == .top { receiptPlaceholder }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.5)))

            Text("Shown as it prints on \(model.printer.name): black and white, \(model.printer.dotsPerLine) dots wide. The grey bars stand in for your receipt.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Grey bars that stand in for the receipt, so the preview shows which side of it the logo is on.
    private var receiptPlaceholder: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                ForEach([0.9, 0.6, 0.8, 0.45], id: \.self) { fraction in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.35))
                        .frame(width: max(0, (proxy.size.width - 24) * fraction), height: 8)
                }
            }
            .padding(12)
        }
        .frame(height: 4 * 8 + 3 * 8 + 24)
    }
}
