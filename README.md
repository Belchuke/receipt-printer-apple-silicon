# Receipt Printer for Apple Silicon

Native Apple Silicon. No Rosetta. A macOS print service for Epson USB receipt printers.

It replaces Epson's legacy Intel-based macOS printing components while preserving the standard macOS printing workflow used by existing applications.

## How it works

```text
Application
    ↓
macOS Print / CUPS
    ↓
Local IPP Printer
    ↓
Native ARM64 Compatibility Service
    ↓
ESC/POS
    ↓
USB
    ↓
Epson receipt printer
```

Applications that already use the built-in macOS printing system do not need to be modified.

## Features

- Native Apple Silicon / ARM64
- Epson ESC/POS USB receipt printers (see [Supported printers](#supported-printers))
- Standard macOS printing through CUPS
- No Rosetta dependency
- No DriverKit or system extension
- Native Swift implementation
- Direct USB communication through `IOUSBHost`
- Local IPP print service
- Loopback-only networking
- No Bonjour or network printer advertising
- Printer queue is not shared
- 80 mm paper, plus a 58 mm preset for the TM-T88V
- Raster printing at each printer's native resolution (180 or 203 DPI)
- Automatic paper cutting
- Optional logo printed at the top (or bottom) of every receipt, set in a settings app
- Printer model chosen in the installer
- Signed and notarized macOS installer
- Automatic background service using `launchd`
- Secure automatic updates
- No third-party runtime dependencies

## Supported printers

| Printer | Paper | Resolution | Status |
|---|---|---|---|
| Epson TM-T88V | 80 mm (58 mm preset) | 180 DPI, 512 dots/line | Tested on hardware |
| Epson TM-T88VII | 80 mm | 180 DPI, 512 dots/line | Tested on hardware (USB, status query, raster printing, print darkness) |
| Epson TM-m30II | 80 mm | 203 DPI, 576 dots/line | Tested on hardware (USB, status query and raster printing) |
| Epson TM-m30III | 80 mm | 203 DPI, 576 dots/line | Tested on hardware (USB, status query, raster printing, tuned print darkness) |

Other Epson ESC/POS printers (for example the TM-T88IV) are untested. Reports and USB diagnostics from other models are welcome.

The installer asks which printer you have. The choice is stored in `printer.json` and read by the service. To change it later, run `receipt-printer-config set-model tm-m30iii` (or `tm-t88v`, `tm-t88vii`, `tm-m30ii`) and restart the service, or run the installer again. The tools below also take `--model tm-t88v`, `--model tm-t88vii`, `--model tm-m30ii` or `--model tm-m30iii`.

## Requirements

- macOS 13 or newer
- Apple Silicon Mac
- A supported Epson printer
- USB connection to the printer

## Installation

Download the latest customer installer:

**[Download the latest installer from GitHub Releases](https://github.com/Belchuke/receipt-printer-apple-silicon/releases/latest)**

Open the downloaded `.pkg` and follow the macOS installer.

The installer:

- asks which printer model you use
- installs the native compatibility service
- starts the background service
- creates the `Receipt_Printer` printer queue
- configures the printer to use the local IPP service
- installs the automatic updater

Existing Epson printer drivers and queues are not removed or modified.

Upgrading from the earlier "TM-T88V macOS Compatibility" releases (v0.2.0 and older): this project was renamed and its identifiers changed, so those installs do not update automatically. Install the new package manually. The installer removes the old service, updater, files and `TMT88V_Compat` queue, and creates `Receipt_Printer`.

After installation, applications can print to:

```text
Receipt_Printer
```

like any other macOS printer.

## Print darkness

The TM-T88VII printed too pale out of the box (12 pt text was hard to read), so this project sends Epson's print density command (`GS ( K`, function 49) before each page. The default is the strongest setting. Other printers are left at their own setting, because the command has only been verified on the TM-T88VII.

Change it in the settings app (the **Print darkness** slider, shown only for printers that support it) or from a terminal:

```bash
/Library/Application\ Support/ReceiptPrinter/bin/receipt-printer-config set-density 80
/Library/Application\ Support/ReceiptPrinter/bin/receipt-printer-config set-density default
```

`0` is the printer's standard darkness and `127` the strongest. Lower it if large black areas look smeared.

The **TM-m30III** printed grey and thin out of the box too. It is tuned on hardware with three settings working together, sent or applied for you:

- print density 127 (adjustable like the TM-T88VII's),
- print speed level 6 (`GS ( K`, function 50), and
- a gamma 2.2 tone curve that makes greys and the edges of small text blacker before the page is turned into dots. It applies to pages and to the logo alike.

A stronger curve (2.6) made small text clog, and the slowest speed was not needed. The TM-T88V, TM-T88VII and TM-m30II are left as they were: no speed command and no tone curve.

## Logo

An image can be printed on every receipt, like the logo option in Epson's old driver. By default it is printed at the **top**, above the receipt. It can be moved to the **bottom**, just before the cut. The image is scaled to the paper width and dithered to black and white.

### Settings app

Open **Receipt Printer Settings** from Applications, or from System Settings > Printers & Scanners > your printer > Options & Supplies > Utility > Open Printer Utility. The installer also opens it at the end of a fresh install, so the logo step is optional.

In the app you can choose or replace the image, turn the logo on or off, pick top or bottom, set the space between the logo and the receipt, and see a preview of the printed result. Changes apply to the next print job, and there is no service restart. Only administrator accounts can change the settings.

### Command line

The same settings are available from a terminal:

```bash
/Library/Application\ Support/ReceiptPrinter/bin/receipt-printer-config set-logo ~/Pictures/logo.png
/Library/Application\ Support/ReceiptPrinter/bin/receipt-printer-config set-position bottom
```

| Command | What it does |
|---|---|
| `show` | Shows the model and logo settings |
| `set-logo IMAGE` | Stores a PNG or JPEG and turns the logo on |
| `set-position top\|bottom` | Prints the logo above (default) or below the receipt |
| `enable-logo` / `disable-logo` | Turns the stored logo on or off |
| `remove-logo` | Turns it off and deletes the stored image |
| `set-gap DOTS` | Blank space between the logo and the receipt (default 24) |
| `set-density N\|default` | Print darkness 0-127 for printers that support it (TM-T88VII) |
| `preview FILE` | Writes the 1-bit image that will print to a PNG |

A missing or unreadable logo never blocks a receipt.

## When a print fails

Every failed print job leaves a short text report in **Documents > Receipt Printer Logs** of the person logged in at the Mac. Send it to support. The settings app has an **Open Logs Folder** button for it.

Each report also has a **Printer check** line that says whether the printer plugged in is the model the service is set up for. The most common reason for "nothing prints" is the wrong model chosen in the installer. The check names the printer that is really connected and how to fix it: run the installer again and choose that printer, or run `receipt-printer-config set-model <model>` and then restart the service. It also notices when no Epson printer is visible at all, which points to the cable, the power switch or the power adapter. The service writes the same check to its own log when it starts (`printer_check`).

A report holds the error message, the time, the printer model and settings, the software and macOS versions, the Epson USB devices the Mac can see at that moment, and the last lines of the service's own log. It never contains what was printed, the job's name or the user's name, and it has no file paths. The newest 50 reports are kept. If the Documents folder can't be written (nobody is logged in, or macOS blocks it), the report is saved in `/Library/Logs/ReceiptPrinter/failures` instead. Use `receipt-printer-service --no-failure-reports` to turn it off.

## Restarting the service

The print service runs in the background as the launchd job `com.belchuke.receiptprinter.service`. Settings such as the logo apply to the next print without a restart, but changing the printer model needs one. Any of these works:

- Run the installer again and choose the printer. This is the easiest way.
- Restart the Mac.
- In Terminal: `sudo launchctl kickstart -k system/com.belchuke.receiptprinter.service`

## Automatic Updates

Starting with v0.2.0, the compatibility layer updates itself automatically in the background.

Updates are downloaded only from the official GitHub Releases for this repository and are verified before installation.

The updater verifies the package signature, Apple Developer team, package identity, version, and Apple notarization before an update can be installed.

No update prompts or user interaction are required.

`ReceiptPrinter.pkg` in each GitHub release is reserved for the automatic updater. For manual installation, use the versioned package such as `ReceiptPrinter-0.3.1.pkg`.

## Building from source

Requires Swift 6 and the Xcode Command Line Tools.

```bash
./scripts/build.sh
```

Run the test suite with:

```bash
./scripts/test.sh
```

Build output is placed in:

```text
dist/
```

## Tools

### Printer diagnostics

```bash
dist/receipt-printer-diag --status
```

Displays the connected printer's USB information and status. Add `--model tm-t88vii`, `--model tm-m30ii` or `--model tm-m30iii` for those printers.

### Direct print test

```bash
dist/receipt-printer-test
```

Prints a test receipt directly through USB without using CUPS.

### Raster test

```bash
dist/receipt-printer-raster-test --pattern
```

Prints the built-in raster test pattern.

### Print service

```bash
dist/receipt-printer-service
```

Starts the local IPP compatibility service.

The default endpoint is:

```text
ipp://127.0.0.1:8632/ipp/print
```

## Uninstall

The installed package includes an uninstaller:

```bash
sudo "/Library/Application Support/ReceiptPrinter/uninstall.sh" --yes
```

The uninstaller removes only resources created by this project.

Existing Epson printer drivers, Epson queues, and unrelated CUPS configuration are left untouched.

## Known Limitations

- Only the printers in the table above are tested
- The settings app opens from the printer's Utility button but is not an embedded panel inside System Settings
- The Utility button depends on a CUPS PPD, a mechanism CUPS marks as deprecated; the app still opens from Applications if it stops working
- Epson Vendor Class USB mode has not been fully hardware-tested
- Cash drawer and buzzer controls are not exposed through the macOS print interface
- Epson-specific printer options may not have direct equivalents in the driverless print queue
- Compatibility with application-specific printer settings may vary

## License

See [LICENSE](LICENSE).
