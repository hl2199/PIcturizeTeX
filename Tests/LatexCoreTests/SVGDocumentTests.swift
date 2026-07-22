import Testing
@testable import LatexCore

/// A representative MathJax root tag, copied from real output of
/// `x = \sin\left(\frac{\pi}{2}\right)`.
private let sampleSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="12.453ex" height="4.145ex" role="img" \
focusable="false" viewBox="0 -1146 5504.2 1832" style="vertical-align: -1.552ex;">\
<g stroke="currentColor" fill="currentColor" stroke-width="0"><path d="M52 289z"/></g></svg>
"""

@Suite("SVG post-processing")
struct SVGDocumentTests {

    @Test("ex dimensions become pixels at the default scale")
    func convertsExToPixels() {
        let out = SVGDocument.finalize(rawSVG: sampleSVG, widthEx: 12.453, heightEx: 4.145,
                                       pixelsPerEx: 8, color: .black)
        // 12.453 * 8 = 99.624, 4.145 * 8 = 33.16
        #expect(out.contains("width=\"99.624px\""))
        #expect(out.contains("height=\"33.16px\""))
        #expect(!out.contains("ex\""), "no ex-valued dimensions should remain")
    }

    @Test("a manual scale factor is honoured")
    func honoursManualScale() {
        let out = SVGDocument.finalize(rawSVG: sampleSVG, widthEx: 10, heightEx: 2,
                                       pixelsPerEx: 15, color: .black)
        #expect(out.contains("width=\"150px\""))
        #expect(out.contains("height=\"30px\""))
    }

    @Test("white mode stamps white")
    func whiteStampsWhite() {
        let out = SVGDocument.finalize(rawSVG: sampleSVG, widthEx: 1, heightEx: 1,
                                       pixelsPerEx: 8, color: .white)
        #expect(out.contains("color: white;"))
    }

    @Test("a colour is appended without discarding MathJax's own style")
    func colorPreservesExistingStyle() {
        let out = SVGDocument.finalize(rawSVG: sampleSVG, widthEx: 1, heightEx: 1,
                                       pixelsPerEx: 8, color: .custom("#0066cc"))
        #expect(out.contains("color: #0066cc;"))
        #expect(out.contains("vertical-align: -1.552ex;"), "MathJax's own style must survive")
    }

    @Test("black mode stamps black")
    func blackStampsBlack() {
        let out = SVGDocument.finalize(rawSVG: sampleSVG, widthEx: 1, heightEx: 1,
                                       pixelsPerEx: 8, color: .black)
        #expect(out.contains("color: black;"))
    }

    @Test("a blank custom colour falls back to black")
    func blankCustomColorIsBlack() {
        let out = SVGDocument.finalize(rawSVG: sampleSVG, widthEx: 1, heightEx: 1,
                                       pixelsPerEx: 8, color: .custom("   "))
        #expect(out.contains("color: black;"), "a blank colour field must not emit invalid CSS")
    }

    @Test("attribute names are not matched as substrings")
    func doesNotMatchSubstrings() {
        // `width` also occurs inside `stroke-width`, which must not be rewritten.
        let out = SVGDocument.finalize(rawSVG: sampleSVG, widthEx: 1, heightEx: 1,
                                       pixelsPerEx: 8, color: .black)
        #expect(out.contains("stroke-width=\"0\""), "stroke-width must be untouched")
    }

    @Test("the root tag scan is quote aware")
    func rootTagScanIsQuoteAware() {
        // A `>` inside an attribute value must not end the tag early.
        let tricky = "<svg width=\"1ex\" height=\"1ex\" data-latex=\"a > b\"><g/></svg>"
        let range = SVGDocument.rootTagRange(in: tricky)
        #expect(range != nil)
        #expect(String(tricky[range!]) == "<svg width=\"1ex\" height=\"1ex\" data-latex=\"a > b\">")
    }

    @Test("dimensions are inserted when the root tag has none")
    func addsMissingDimensions() {
        let bare = "<svg xmlns=\"http://www.w3.org/2000/svg\"><g/></svg>"
        let out = SVGDocument.finalize(rawSVG: bare, widthEx: 2, heightEx: 3,
                                       pixelsPerEx: 10, color: .black)
        #expect(out.contains("width=\"20px\""))
        #expect(out.contains("height=\"30px\""))
    }

    @Test("input that is not SVG is returned unchanged")
    func malformedInputUnchanged() {
        let junk = "not svg at all"
        #expect(SVGDocument.finalize(rawSVG: junk, widthEx: 1, heightEx: 1,
                                     pixelsPerEx: 8, color: .black) == junk)
    }

    @Test("a standalone file carries an XML declaration")
    func standaloneFileHasDeclaration() {
        #expect(SVGDocument.standaloneFile(svg: sampleSVG).hasPrefix("<?xml version=\"1.0\""))
    }

    @Test("number formatting drops trailing zeros")
    func numberFormatting() {
        #expect(SVGDocument.format(150.0) == "150")
        #expect(SVGDocument.format(99.624) == "99.624")
        #expect(SVGDocument.format(33.160) == "33.16")
    }
}

@Suite("Scaling")
struct ScalingTests {

    @Test("the default factor matches the website")
    func defaultFactor() {
        #expect(Scaling.defaultPixelsPerEx == 8.0)
        #expect(abs(Scaling.pixels(ex: 12.453, pixelsPerEx: 8) - 99.624) < 1e-9)
    }

    @Test("a non-positive scale falls back to the default", arguments: [0.0, -5.0, Double.nan])
    func nonPositiveScaleFallsBack(factor: Double) {
        // The manual scale field is free text the user can empty or zero while
        // typing; a zero-sized image is worse than falling back.
        #expect(Scaling.pixels(ex: 10, pixelsPerEx: factor) == 80)
    }
}
