import Foundation

/// How the equation is coloured. Every export carries an explicit colour, so
/// the file looks the same wherever it lands.
public enum ColorMode: Equatable, Codable, Sendable {
    case black
    case white
    /// Any CSS colour string, e.g. `#0066cc` or `rebeccapurple`.
    case custom(String)

    /// The CSS colour to stamp onto the SVG. A blank custom value falls back to
    /// black rather than emitting an invalid style.
    public var cssColor: String {
        switch self {
        case .black: return "black"
        case .white: return "white"
        case .custom(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "black" : trimmed
        }
    }
}

/// How MathJax's `ex` units are converted to pixels.
public enum ScaleMode: Equatable, Codable, Sendable {
    /// The website's default: 1 ex = 8 px.
    case standard
    /// Match a CSS font, e.g. `20px Lato`. The pixels-per-ex figure is measured
    /// by the render engine, since it requires a layout engine to determine.
    case matchFont(String)
    /// An explicit pixels-per-ex figure.
    case manual(Double)
}

public enum Scaling {
    /// 1 ex = 8 px, matching viereck.ch's default.
    public static let defaultPixelsPerEx: Double = 8.0

    /// Converts a dimension in `ex` units to pixels.
    ///
    /// Non-finite or non-positive scale factors fall back to the default rather
    /// than producing a degenerate image, because the manual scale field is a
    /// free text entry the user can empty or set to zero mid-edit.
    public static func pixels(ex: Double, pixelsPerEx: Double) -> Double {
        guard pixelsPerEx.isFinite, pixelsPerEx > 0, ex.isFinite else {
            return ex * defaultPixelsPerEx
        }
        return ex * pixelsPerEx
    }
}

/// Everything that affects the appearance of a render.
public struct RenderSettings: Equatable, Codable, Sendable {
    public var displayMode: Bool
    public var color: ColorMode
    public var scale: ScaleMode

    public init(displayMode: Bool = true,
                color: ColorMode = .black,
                scale: ScaleMode = .standard) {
        self.displayMode = displayMode
        self.color = color
        self.scale = scale
    }
}

/// A file format the equation can be exported as.
public enum ExportFormat: String, Equatable, Codable, Sendable, CaseIterable {
    case svg, pdf, png

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .svg: return "SVG"
        case .pdf: return "PDF"
        case .png: return "PNG"
        }
    }
}
