import AppKit
import LatexCore
import UniformTypeIdentifiers

extension ExportFormat {
    var contentType: UTType {
        switch self {
        case .svg: return .svg
        case .pdf: return .pdf
        case .png: return .png
        }
    }
}

@MainActor
extension AppModel {

    /// Puts every format on the pasteboard as alternative representations of a
    /// single item.
    ///
    /// The receiving application picks the representation it understands, which
    /// is the only way to make one Copy command work for Keynote, Figma and
    /// Slack at once. PDF is registered first so that applications accepting
    /// several formats prefer the vector one.
    func copyToPasteboard() async {
        do {
            let pdf = try await data(for: .pdf)
            let png = try await data(for: .png)
            let svg = try await data(for: .svg)

            let item = NSPasteboardItem()
            item.setData(pdf, forType: .pdf)
            item.setData(png, forType: .png)
            item.setData(svg, forType: NSPasteboard.PasteboardType(UTType.svg.identifier))

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([item])

            recordInHistory()
        } catch {
            present(error)
        }
    }

    /// Copies just the SVG markup as text, for pasting into an editor.
    func copySVGSource() {
        guard let svg = renderedSVG else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(SVGDocument.standaloneFile(svg: svg), forType: .string)
    }

    /// Asks where to save, then writes the chosen format.
    func save(format: ExportFormat) async {
        guard renderedSVG != nil else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "equation.\(format.fileExtension)"
        panel.canCreateDirectories = true
        // Re-opening in the last used folder saves a navigation on every export,
        // which matters when saving a run of figures into one directory.
        if let remembered = UserDefaults.standard.url(forKey: Self.lastSaveDirectoryKey) {
            panel.directoryURL = remembered
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.deletingLastPathComponent(), forKey: Self.lastSaveDirectoryKey)

        do {
            try await data(for: format).write(to: url, options: .atomic)
            recordInHistory()
        } catch {
            present(error)
        }
    }

    /// Supplies the dragged file lazily, so nothing is exported unless a drop
    /// actually happens.
    func makeDragProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let format = dragFormat
        provider.suggestedName = "equation.\(format.fileExtension)"

        provider.registerFileRepresentation(forTypeIdentifier: format.contentType.identifier,
                                            fileOptions: [],
                                            visibility: .all) { completion in
            Task { @MainActor in
                do {
                    let bytes = try await self.data(for: format)
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("equation-\(UUID().uuidString)")
                        .appendingPathExtension(format.fileExtension)
                    try bytes.write(to: url, options: .atomic)
                    self.recordInHistory()
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private static let lastSaveDirectoryKey = "lastSaveDirectory"

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Export failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
