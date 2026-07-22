import Foundation

/// Post-processing of MathJax's raw SVG output.
///
/// MathJax emits dimensions in `ex` units and draws using `currentColor`, which
/// makes its output convenient to embed in a web page but unsuitable as a
/// standalone file: an `ex` means nothing without surrounding text, and
/// `currentColor` with nothing to inherit from renders black by accident rather
/// than by intent. These functions turn that output into a self-contained file.
///
/// This is deliberately string surgery on the root `<svg>` tag only, rather than
/// a full XML parse. Nothing below the root is touched.
public enum SVGDocument {

    /// Rewrites the root element with pixel dimensions and, optionally, a colour.
    ///
    /// - Parameters:
    ///   - rawSVG: MathJax's output.
    ///   - widthEx: width reported by MathJax, in `ex`.
    ///   - heightEx: height reported by MathJax, in `ex`.
    ///   - pixelsPerEx: conversion factor from the active scale mode.
    ///   - color: colour to apply, or `.inherit` to leave `currentColor` alone.
    public static func finalize(rawSVG: String,
                                widthEx: Double,
                                heightEx: Double,
                                pixelsPerEx: Double,
                                color: ColorMode) -> String {
        guard let head = rootTagRange(in: rawSVG) else { return rawSVG }

        var tag = String(rawSVG[head])
        let widthPx = Scaling.pixels(ex: widthEx, pixelsPerEx: pixelsPerEx)
        let heightPx = Scaling.pixels(ex: heightEx, pixelsPerEx: pixelsPerEx)

        tag = setAttribute(tag, name: "width", value: format(widthPx) + "px")
        tag = setAttribute(tag, name: "height", value: format(heightPx) + "px")

        if let css = color.cssColor {
            let existing = attributeValue(tag, name: "style") ?? ""
            // Appending rather than replacing preserves MathJax's vertical-align,
            // which callers embedding the SVG inline still rely on.
            var merged = existing.trimmingCharacters(in: .whitespaces)
            if !merged.isEmpty && !merged.hasSuffix(";") { merged += ";" }
            merged += " color: \(css);"
            tag = setAttribute(tag, name: "style", value: merged.trimmingCharacters(in: .whitespaces))
        }

        return rawSVG.replacingCharacters(in: head, with: tag)
    }

    /// Wraps an SVG fragment as a standalone file, with XML declaration.
    public static func standaloneFile(svg: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n" + svg + "\n"
    }

    /// The pixel size of a finalized SVG, used to size the PDF page.
    public static func pixelSize(widthEx: Double,
                                 heightEx: Double,
                                 pixelsPerEx: Double) -> (width: Double, height: Double) {
        (Scaling.pixels(ex: widthEx, pixelsPerEx: pixelsPerEx),
         Scaling.pixels(ex: heightEx, pixelsPerEx: pixelsPerEx))
    }

    // MARK: - Root tag handling

    /// Range of the opening `<svg ...>` tag, quote-aware so that a `>` inside an
    /// attribute value does not end the tag early.
    static func rootTagRange(in svg: String) -> Range<String.Index>? {
        guard let start = svg.range(of: "<svg") else { return nil }
        var index = start.upperBound
        var quote: Character? = nil
        while index < svg.endIndex {
            let char = svg[index]
            if let active = quote {
                if char == active { quote = nil }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == ">" {
                return start.lowerBound..<svg.index(after: index)
            }
            index = svg.index(after: index)
        }
        return nil
    }

    static func attributeValue(_ tag: String, name: String) -> String? {
        guard let range = attributeValueRange(tag, name: name) else { return nil }
        return String(tag[range])
    }

    /// Sets an attribute, replacing it in place if present and inserting it just
    /// after the element name otherwise.
    static func setAttribute(_ tag: String, name: String, value: String) -> String {
        if let range = attributeValueRange(tag, name: name) {
            return tag.replacingCharacters(in: range, with: escape(value))
        }
        guard let nameEnd = tag.range(of: "<svg")?.upperBound else { return tag }
        return tag.replacingCharacters(in: nameEnd..<nameEnd, with: " \(name)=\"\(escape(value))\"")
    }

    /// Range of an attribute's value, excluding the surrounding quotes.
    private static func attributeValueRange(_ tag: String, name: String) -> Range<String.Index>? {
        var searchStart = tag.startIndex
        while let found = tag.range(of: name, range: searchStart..<tag.endIndex) {
            searchStart = found.upperBound

            // Reject substring hits: `width` must not match inside `stroke-width`.
            let before = found.lowerBound
            if before > tag.startIndex {
                let prev = tag[tag.index(before: before)]
                if prev.isLetter || prev.isNumber || prev == "-" || prev == "_" { continue }
            }

            // Skip whitespace, require '=', skip whitespace, require a quote.
            var index = found.upperBound
            while index < tag.endIndex, tag[index].isWhitespace { index = tag.index(after: index) }
            guard index < tag.endIndex, tag[index] == "=" else { continue }
            index = tag.index(after: index)
            while index < tag.endIndex, tag[index].isWhitespace { index = tag.index(after: index) }
            guard index < tag.endIndex, tag[index] == "\"" || tag[index] == "'" else { continue }

            let quote = tag[index]
            let valueStart = tag.index(after: index)
            guard let closing = tag[valueStart...].firstIndex(of: quote) else { return nil }
            return valueStart..<closing
        }
        return nil
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "\"", with: "&quot;")
             .replacingOccurrences(of: "<", with: "&lt;")
    }

    /// Trims trailing zeros so dimensions read `99.6px` rather than `99.600000px`.
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded() && abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        return String(rounded)
    }
}
