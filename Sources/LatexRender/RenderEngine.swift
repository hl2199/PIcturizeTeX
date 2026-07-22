import Foundation
import WebKit

/// Raw output of a MathJax render, before scaling or colouring.
///
/// Dimensions are in `ex` units because that is what MathJax emits; converting
/// them to pixels is the job of `LatexCore.Scaling`.
public struct RenderResult: Sendable, Equatable {
    public let svg: String
    public let widthEx: Double
    public let heightEx: Double

    public init(svg: String, widthEx: Double, heightEx: Double) {
        self.svg = svg
        self.widthEx = widthEx
        self.heightEx = heightEx
    }
}

public enum RenderError: Error, Equatable {
    /// The TeX source was invalid. Carries MathJax's own message.
    case invalidTeX(String)
    /// The engine itself failed -- resources missing, JS threw, page never loaded.
    case engineFailure(String)
}

/// Drives MathJax inside an offscreen `WKWebView`.
///
/// This class is the only place in the application where JavaScript runs. It
/// exposes one operation, `render`, and holds no state beyond the web view and
/// its readiness.
@MainActor
public final class RenderEngine: NSObject {
    private let webView: WKWebView
    private var isReady = false

    public override init() {
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .init(x: 0, y: 0, width: 1024, height: 1024),
                                 configuration: config)
        super.init()
    }

    /// Loads MathJax and waits until it has finished initialising.
    ///
    /// Safe to call repeatedly; subsequent calls return immediately.
    public func start() async throws {
        if isReady { return }

        guard let htmlURL = Bundle.module.url(forResource: "render", withExtension: "html") else {
            throw RenderError.engineFailure("render.html missing from the app bundle.")
        }
        // MathJax is loaded by <script src>, so the web view needs read access to
        // the whole resource directory, not just the HTML file.
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())

        // MathJax signals readiness by setting a flag once its startup promise
        // resolves. Polling avoids a message-handler round trip and keeps the
        // JS side to the single render function.
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let ready = try? await webView.evaluateJavaScript("window.mathJaxReady === true") as? Bool,
               ready {
                isReady = true
                return
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        throw RenderError.engineFailure("MathJax did not finish loading within 20 seconds.")
    }

    /// Renders TeX source to SVG.
    ///
    /// - Parameters:
    ///   - latex: the equation source.
    ///   - preamble: macro definitions prepended to the source; may be empty.
    ///   - displayMode: `true` for display math, `false` for inline.
    /// - Throws: `RenderError.invalidTeX` when the source is malformed, which
    ///   callers should treat as recoverable and non-destructive.
    public func render(latex: String, preamble: String, displayMode: Bool) async throws -> RenderResult {
        try await start()

        // Passing the strings as JSON literals sidesteps every quoting and
        // backslash-escaping hazard -- and TeX is made of backslashes.
        let latexJSON = try jsonStringLiteral(latex)
        let preambleJSON = try jsonStringLiteral(preamble)
        let js = "window.renderEquation(\(latexJSON), \(preambleJSON), \(displayMode))"

        let raw: Any?
        do {
            raw = try await webView.evaluateJavaScript(js)
        } catch {
            throw RenderError.engineFailure("JavaScript evaluation failed: \(error.localizedDescription)")
        }

        guard let jsonText = raw as? String, let data = jsonText.data(using: .utf8) else {
            throw RenderError.engineFailure("Render function returned an unexpected type.")
        }
        struct Payload: Decodable {
            let svg: String?
            let widthEx: Double
            let heightEx: Double
            let error: String?
            let kind: String?
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw RenderError.engineFailure("Could not decode render output: \(error.localizedDescription)")
        }

        if let message = payload.error {
            // A malformed equation is an expected, recoverable event; anything
            // else means the engine is broken and should not be papered over.
            throw payload.kind == "tex"
                ? RenderError.invalidTeX(message)
                : RenderError.engineFailure(message)
        }
        guard let svg = payload.svg else {
            throw RenderError.engineFailure("Render reported success but produced no SVG.")
        }
        return RenderResult(svg: svg, widthEx: payload.widthEx, heightEx: payload.heightEx)
    }

    /// Encodes a Swift string as a JavaScript string literal, including quotes.
    private func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RenderError.engineFailure("Could not encode input as JSON.")
        }
        return text
    }
}
