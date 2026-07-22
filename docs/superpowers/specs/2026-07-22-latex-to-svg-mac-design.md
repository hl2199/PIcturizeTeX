# LaTeX to SVG — macOS app

**Date:** 2026-07-22
**Status:** Approved design

A native macOS app that renders LaTeX equations to vector graphics, reproducing every
feature of [viereck.ch/latex-to-svg](https://viereck.ch/latex-to-svg/) and adding the
native integrations a web page cannot provide.

Working name: `LatexToSVG`. The shipping name is deferred; it affects only the bundle
identifier and display name, not the implementation.

## Motivation

Two workflows drive the design:

1. **Paste an equation into slides or documents** — Keynote, Word, Figma, Illustrator.
2. **Save `.svg` files to disk** — figures destined for Inkscape or a paper.

The website serves only the second, and only partly: it emits SVG, which is the format
slide software handles worst. The app's job is to make both workflows one keystroke.

## Constraints

- **MathJax is JavaScript.** Reimplementing TeX layout natively is out of scope by
  several orders of magnitude, so a JS engine renders the math regardless of the shell.
  The design confines that JS to the smallest possible surface.
- **Offline.** MathJax ships as `mathjax@4.1.3/tex-svg.js`, a single 1.85 MB
  self-contained file with fonts embedded. Vendor it into the bundle; no build step,
  no network at runtime.
- **macOS only.** SwiftUI + AppKit.

## Architecture

Three layers, isolating the untestable part.

### 1. Render engine — the only JavaScript

An offscreen `WKWebView` loads a bundled local HTML page that imports `tex-svg.js`
configured for SVG output. Swift drives it through a single entry point:

```
render(latex, preamble, displayMode, color, scaleMode) -> { svg, widthPx, heightPx, error }
```

That signature is the entire JS surface area. Everything else is Swift.

**Scaling.** MathJax sizes SVG output in `ex` units; the engine rewrites the root
`width`/`height` to pixels using a px-per-ex factor supplied by Swift. Three modes:

| Mode | Factor |
|---|---|
| Default | 8 px per ex |
| Match a font | measured ex-height of the chosen CSS font |
| Manual | user-supplied px per ex |

**Color.** Applied as a `color` style on the container; MathJax's SVG inherits via
`currentColor`. Three modes: MathJax default (inherit), black, custom CSS color.

**Preamble.** A global macro block prepended to the source before rendering. MathJax
handles `\newcommand` natively. Global rather than per-equation, matching how a paper
preamble is used.

### 2. Export pipeline

SVG is the source of truth; the other formats derive from it, each step staying vector
as long as possible.

- **SVG** — the returned string, written directly.
- **PDF** — the SVG loaded into an offscreen webview sized to exact points, then
  `WKWebView.createPDF` over a tight bounding rect. True vector output.
- **PNG** — the PDF drawn into a `CGBitmapContext` at the chosen DPI with a transparent
  background. Deriving from the PDF rather than screenshotting the preview keeps it
  crisp at any DPI.

### 3. SwiftUI shell

Editor, preview, settings, history, and the native integrations.

## User interface

Deliberately not the website's layout. Three panes, the outer two collapsible:

```
┌──────────┬─────────────────────────┬──────────┐
│ History  │   ⟨ live preview ⟩      │ Settings │
│ (hidden  │                         │          │
│  by      ├─────────────────────────┤          │
│ default) │  \frac{\pi}{2}          │          │
│          │  [ LaTeX editor ]       │          │
└──────────┴─────────────────────────┴──────────┘
   [Copy]  [Save… ▾]        drag preview → anywhere
```

- **Preview above, editor below.** The result is looked at more than the source.
- **The preview is the drag handle.** Dragging it into Keynote or Finder writes a file
  via `NSFilePromiseProvider`, in the format set by a "drag format" preference that
  defaults to PDF. A drag produces exactly one file, so unlike the clipboard it must
  commit to a single format.
- **Copy takes no format argument** and writes all three representations to one
  pasteboard item. Keynote takes the PDF, Figma the SVG, Slack the PNG. The receiving
  app decides, because it is the only party that knows what it can accept.
- **Save… offers a format chooser** (SVG / PDF / PNG) in the save panel, since a file
  on disk, like a drag, is a single format.
- **History is collapsed by default**, with a toolbar toggle and a View-menu item; the
  visibility state persists. It is an opt-in feature for those who want it.
- **Settings** carries the site's controls, with one upgrade: the "match a font" CSS
  string becomes a native font picker, resolving to the same px-per-ex factor.

## Feature parity

| Website | App |
|---|---|
| LaTeX input, auto-update toggle | Editor with debounced live render; auto-update toggle kept |
| Color: default / black / CSS string | Same three modes, CSS field plus a native color well |
| Scale: default / font-match / manual | Same three modes |
| Display mode toggle | Same |
| SVG source view + copy | Collapsible source drawer, copyable |
| Download SVG | ⌘S → SVG / PDF / PNG, last folder remembered |
| — | Multi-format clipboard, drag-out, history, macro preamble |

## Persistence

`~/Library/Application Support/LatexToSVG/`:

- `history.json` — one entry per render: LaTeX source, settings, timestamp.
- `preamble.tex` — the global macro block.

Thumbnails are re-rendered lazily rather than stored, keeping history a small text file
a user could edit by hand.

## Error handling

Invalid TeX produces MathJax `merror` output, not a crash. On error the app shows the
message beneath the editor and **keeps the last good preview on screen**, so a
half-typed `\frac{` does not blank the canvas mid-keystroke.

## Testing

The webview is the part that resists testing, so logic lives outside it.

**Unit**
- ex→px scaling across all three modes, including the font-measurement path.
- Pasteboard item assembly: one item carrying PDF, PNG, and SVG representations.
- History store round-trip: write, read, malformed-file recovery.
- PNG raster dimensions at a given DPI.

**Integration**
- Headless render of ~6 known equations; golden-file comparison on SVG structure and
  on dimensions within tolerance.
- Invalid input returns a populated `error` field and preserves the prior render.

## Out of scope

Global hotkey and menu-bar summoning; cross-platform builds; equation editing by direct
manipulation; MathML or AsciiMath input.
