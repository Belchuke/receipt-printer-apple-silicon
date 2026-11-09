public extension PrinterModel {
    /// Selectable models, keyed by the identifier used for `--model` and stored in printer.json.
    /// Keep in sync with MODEL_IDS in scripts/config.sh, UpdaterConstants.knownModelIDs and the choices in pkg/distribution.xml.template.
    static let registry: [(id: String, model: PrinterModel)] = [
        ("tm-t88v", .tmT88V80mm),
        ("tm-t88vii", .tmT88VII80mm),
        ("tm-m30ii", .tmM30II80mm),
    ]

    static var registryIDs: [String] { registry.map(\.id) }

    static func named(_ id: String) -> PrinterModel? {
        registry.first { $0.id == id.lowercased() }?.model
    }
}
