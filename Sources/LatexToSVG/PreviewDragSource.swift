// @preconcurrency: NSFilePromiseProviderDelegate predates Swift concurrency and
// declares its completion handler non-Sendable, though AppKit may call it from
// any queue. The annotation lets the conformance keep the truthful @Sendable.
@preconcurrency import AppKit
import LatexCore
import SwiftUI
import UniformTypeIdentifiers

/// A transparent layer over the preview that lets the equation be dragged out
/// as a file.
///
/// The preview itself is a `WKWebView`, and AppKit delivers mouse events to the
/// deepest view under the pointer -- the web view -- so a SwiftUI `.onDrag`
/// attached above it never receives the gesture. This view sits on top of the
/// web view, takes the mouse events itself, and starts a classic AppKit drag
/// session carrying an `NSFilePromiseProvider`, the drag flavour every macOS
/// drop target (Finder, Keynote, Mail, ...) understands.
struct PreviewDragSource: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.model = model
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.model = model
    }
}

/// A file promise that also carries the equation as concrete PDF and PNG data.
///
/// The promise alone only works with targets that implement the file-promise
/// contract (Finder, Mail). Document apps such as PowerPoint and Illustrator
/// ignore promises and look for image data on the drag pasteboard -- the same
/// flavours a drag from a web browser carries. Offering both makes the one
/// drag work everywhere: file-oriented targets take the promise, image-oriented
/// targets take the data.
final class EquationPromiseProvider: NSFilePromiseProvider {
    var pdfData: Data?
    var pngData: Data?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if pdfData != nil { types.append(.pdf) }
        if pngData != nil { types.append(.png) }
        return types
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType,
                                 pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        switch type {
        case .pdf, .png: return []
        default: return super.writingOptions(forType: type, pasteboard: pasteboard)
        }
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .pdf: return pdfData
        case .png: return pngData
        default: return super.pasteboardPropertyList(forType: type)
        }
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    weak var model: AppModel?

    /// `NSFilePromiseProvider` does not retain its delegate, so the delegate of
    /// the drag in flight is kept alive here. Replaced on the next drag; a
    /// single mouse cannot run two drags at once.
    private var promiseDelegate: EquationFilePromiseDelegate?

    /// Allows dragging out of a window that is not frontmost, which is the
    /// normal state when the drop target is the app being dragged into.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDragged(with event: NSEvent) {
        guard let model, model.renderedSVG != nil else { return }

        let format = model.dragFormat
        let delegate = EquationFilePromiseDelegate(
            fileName: "equation.\(format.fileExtension)",
            makeData: { @MainActor [weak model] in
                guard let model else { throw CocoaError(.userCancelled) }
                let data = try await model.data(for: format)
                model.recordInHistory()
                return data
            }
        )
        promiseDelegate = delegate

        let provider = EquationPromiseProvider(fileType: format.contentType.identifier,
                                               delegate: delegate)
        // Concrete flavours come from the cache filled after the last render;
        // pasteboard data is demanded synchronously, so this is the only
        // moment it can be attached.
        if let cache = model.freshExportCache {
            provider.pdfData = cache.pdf
            provider.pngData = cache.png
        }
        let item = NSDraggingItem(pasteboardWriter: provider)

        let image = dragImage()
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - image.size.width / 2,
                                     y: point.y - image.size.height / 2,
                                     width: image.size.width,
                                     height: image.size.height),
                              contents: image)

        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    /// Right-click copies the equation. The menu lives here rather than in a
    /// SwiftUI `.contextMenu` because this view consumes the preview's mouse
    /// events -- a SwiftUI menu underneath it would never receive the click.
    override func rightMouseDown(with event: NSEvent) {
        guard let model, model.renderedSVG != nil else { return }
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Copy", action: #selector(copyEquation), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyEquation() {
        guard let model else { return }
        Task { await model.copyToPasteboard() }
    }

    /// The equation itself, so the user sees what they are dragging. Falls back
    /// to the destination format's file icon if the SVG cannot be decoded.
    private func dragImage() -> NSImage {
        if let model, let svg = model.renderedSVG,
           let image = NSImage(data: Data(SVGDocument.standaloneFile(svg: svg).utf8)),
           image.size.width > 0 {
            let maxWidth: CGFloat = 240
            if image.size.width > maxWidth {
                let scale = maxWidth / image.size.width
                image.size = NSSize(width: maxWidth, height: image.size.height * scale)
            }
            return image
        }
        return NSWorkspace.shared.icon(for: model?.dragFormat.contentType ?? .pdf)
    }
}

/// Fulfils the file promise when the drop target asks for the file, which can
/// happen after the drag session has visually ended.
final class EquationFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let fileName: String
    private let makeData: @MainActor @Sendable () async throws -> Data

    init(fileName: String, makeData: @escaping @MainActor @Sendable () async throws -> Data) {
        self.fileName = fileName
        self.makeData = makeData
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider,
                                         fileNameForType fileType: String) -> String {
        fileName
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider,
                                         writePromiseTo url: URL,
                                         completionHandler: @escaping @Sendable (Error?) -> Void) {
        // Called on an arbitrary queue; the export pipeline lives on the main
        // actor, so hop there for the data and write from the task.
        Task { @MainActor [makeData] in
            do {
                let data = try await makeData()
                try data.write(to: url, options: .atomic)
                completionHandler(nil)
            } catch {
                NSLog("File promise fulfilment failed: %@", String(describing: error))
                completionHandler(error)
            }
        }
    }
}
