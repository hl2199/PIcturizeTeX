import Foundation
import LatexCore
import LatexRender
import Observation

/// Which colour control the user has selected. Kept separate from `ColorMode`
/// so that switching to Black and back does not discard the typed CSS colour.
enum ColorChoice: String, CaseIterable, Identifiable {
    case inherit, black, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .inherit: return "Container colour"
        case .black: return "Black"
        case .custom: return "Custom"
        }
    }
}

/// Which scaling control is active. Separate from `ScaleMode` for the same
/// reason as `ColorChoice`.
enum ScaleChoice: String, CaseIterable, Identifiable {
    case standard, matchFont, manual
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Default"
        case .matchFont: return "Match a font"
        case .manual: return "Manual"
        }
    }
}

/// All application state, and the only place that talks to the render engine.
@MainActor
@Observable
final class AppModel {

    // MARK: Input

    var latex: String = #"x = \sin \left( \frac{\pi}{2} \right)"# {
        didSet { scheduleRender() }
    }

    var preamble: String = "" {
        didSet {
            preambleStore?.text = preamble
            scheduleRender()
        }
    }

    // MARK: Settings

    var displayMode = true { didSet { scheduleRender() } }
    var colorChoice: ColorChoice = .inherit { didSet { scheduleRender() } }
    var customColorText = "#0066cc" { didSet { scheduleRender() } }
    var scaleChoice: ScaleChoice = .standard { didSet { scheduleRender() } }
    var fontCSSText = "20px Helvetica" { didSet { scheduleRender() } }
    var manualPixelsPerEx: Double = 15 { didSet { scheduleRender() } }

    /// When off, the preview only updates on an explicit request, matching the
    /// website's `auto update` checkbox.
    var autoUpdate = true

    // MARK: Export options

    var pngDPI: Double = 300
    /// A drag produces exactly one file, so unlike the clipboard it must commit
    /// to a single format. PDF pastes as vector into the widest range of apps.
    var dragFormat: ExportFormat = .pdf

    // MARK: View state

    var showHistory = false
    var showSource = false

    // MARK: Output

    private(set) var renderedSVG: String?
    private(set) var pixelWidth: Double = 0
    private(set) var pixelHeight: Double = 0
    /// Non-nil when the current source failed to render. The previous SVG stays
    /// in `renderedSVG` so the preview does not blank out mid-keystroke.
    private(set) var errorMessage: String?
    private(set) var isRendering = false

    private(set) var history: [HistoryEntry] = []

    // MARK: Collaborators

    private let engine = RenderEngine()
    private let exporter = Exporter()
    private var historyStore: HistoryStore?
    private var preambleStore: PreambleStore?
    private var renderTask: Task<Void, Never>?
    /// Last successfully measured factor for the current font string, so a
    /// half-typed font name does not collapse the equation to nothing.
    private var lastMeasuredPixelsPerEx: Double?

    init() {
        // Storage failures must not prevent the app from running; the user
        // simply gets a session without history rather than no app at all.
        historyStore = try? HistoryStore()
        preambleStore = try? PreambleStore()
        preamble = preambleStore?.text ?? ""
        history = historyStore?.entries ?? []
    }

    // MARK: - Settings snapshot

    var colorMode: ColorMode {
        switch colorChoice {
        case .inherit: return .inherit
        case .black: return .black
        case .custom: return .custom(customColorText)
        }
    }

    var scaleMode: ScaleMode {
        switch scaleChoice {
        case .standard: return .standard
        case .matchFont: return .matchFont(fontCSSText)
        case .manual: return .manual(manualPixelsPerEx)
        }
    }

    var currentSettings: RenderSettings {
        RenderSettings(displayMode: displayMode, color: colorMode, scale: scaleMode)
    }

    /// Human-readable summary of the active scale, shown beneath the controls
    /// the way the website reports `1 ex = 8 px`.
    var scaleSummary: String {
        let factor = (try? resolvedPixelsPerExSynchronously()) ?? Scaling.defaultPixelsPerEx
        return "1 ex = \(SVGDocument.format(factor)) px"
    }

    // MARK: - Rendering

    /// Debounces renders so that typing does not queue one job per keystroke.
    func scheduleRender() {
        guard autoUpdate else { return }
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await render()
        }
    }

    /// Renders immediately, used by the manual-refresh button when auto update
    /// is switched off.
    func renderNow() {
        renderTask?.cancel()
        renderTask = Task { await render() }
    }

    private func render() async {
        isRendering = true
        defer { isRendering = false }

        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renderedSVG = nil
            errorMessage = nil
            pixelWidth = 0
            pixelHeight = 0
            return
        }

        do {
            let result = try await engine.render(latex: latex,
                                                 preamble: preamble,
                                                 displayMode: displayMode)
            let factor = await resolvedPixelsPerEx()
            let size = SVGDocument.pixelSize(widthEx: result.widthEx,
                                             heightEx: result.heightEx,
                                             pixelsPerEx: factor)
            renderedSVG = SVGDocument.finalize(rawSVG: result.svg,
                                               widthEx: result.widthEx,
                                               heightEx: result.heightEx,
                                               pixelsPerEx: factor,
                                               color: colorMode)
            pixelWidth = size.width
            pixelHeight = size.height
            errorMessage = nil
        } catch let RenderError.invalidTeX(message) {
            // Recoverable: keep the last good preview on screen.
            errorMessage = message
        } catch let RenderError.engineFailure(message) {
            errorMessage = "Render engine problem: \(message)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedPixelsPerEx() async -> Double {
        switch scaleChoice {
        case .standard:
            return Scaling.defaultPixelsPerEx
        case .manual:
            return manualPixelsPerEx
        case .matchFont:
            // `try?` flattens the engine's optional result, so a nil here means
            // either a measurement failure or an unusable font string.
            if let measured = try? await engine.pixelsPerEx(cssFont: fontCSSText) {
                lastMeasuredPixelsPerEx = measured
                return measured
            }
            return lastMeasuredPixelsPerEx ?? Scaling.defaultPixelsPerEx
        }
    }

    /// The factor without touching the engine, for display purposes only.
    private func resolvedPixelsPerExSynchronously() throws -> Double {
        switch scaleChoice {
        case .standard: return Scaling.defaultPixelsPerEx
        case .manual: return manualPixelsPerEx
        case .matchFont: return lastMeasuredPixelsPerEx ?? Scaling.defaultPixelsPerEx
        }
    }

    // MARK: - Export

    /// Builds the bytes for one format from the current render.
    func data(for format: ExportFormat) async throws -> Data {
        guard let svg = renderedSVG, pixelWidth > 0, pixelHeight > 0 else {
            throw RenderError.engineFailure("There is nothing to export yet.")
        }
        switch format {
        case .svg:
            return Data(SVGDocument.standaloneFile(svg: svg).utf8)
        case .pdf:
            return try await exporter.pdfData(svg: svg, widthPx: pixelWidth, heightPx: pixelHeight)
        case .png:
            let pdf = try await exporter.pdfData(svg: svg, widthPx: pixelWidth, heightPx: pixelHeight)
            return try Exporter.pngData(pdf: pdf, dpi: pngDPI)
        }
    }

    /// Records the current equation in history. Called on export rather than on
    /// render, so the list holds finished equations instead of fragments.
    func recordInHistory() {
        guard let store = historyStore else { return }
        store.record(latex: latex, settings: currentSettings)
        history = store.entries
    }

    func restore(_ entry: HistoryEntry) {
        latex = entry.latex
        displayMode = entry.settings.displayMode

        switch entry.settings.color {
        case .inherit: colorChoice = .inherit
        case .black: colorChoice = .black
        case .custom(let value):
            colorChoice = .custom
            customColorText = value
        }

        switch entry.settings.scale {
        case .standard: scaleChoice = .standard
        case .manual(let value):
            scaleChoice = .manual
            manualPixelsPerEx = value
        case .matchFont(let css):
            scaleChoice = .matchFont
            fontCSSText = css
        }
        renderNow()
    }

    func deleteHistoryEntry(id: UUID) {
        historyStore?.delete(id: id)
        history = historyStore?.entries ?? []
    }

    func clearHistory() {
        historyStore?.clear()
        history = []
    }
}
