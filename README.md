# LaTeX to SVG (macOS)

A native Mac app that renders LaTeX equations to vector graphics — every feature of
[viereck.ch/latex-to-svg](https://viereck.ch/latex-to-svg/), plus the things a web page
can't do. Equations are rendered by a bundled MathJax 4, entirely offline.

## Build and run

Requires only the Xcode Command Line Tools (no Xcode):

```sh
./Scripts/bundle.sh            # builds and assembles build/LatexToSVG.app
open build/LatexToSVG.app
```

Release build: `./Scripts/bundle.sh release`. Tests: `swift test`.

To install, copy `build/LatexToSVG.app` to `/Applications`. The bundle is ad-hoc
signed — fine locally; distributing to others would need a Developer ID and
notarization.

## What it does

- **Live preview** as you type (toggleable), with errors shown without blanking the
  last good render.
- **Copy** (⇧⌘C) puts PDF + PNG + SVG on the clipboard as one item — Keynote takes the
  PDF, Figma the SVG, Slack the PNG.
- **Drag the preview** into any app or Finder to drop a file (format configurable,
  default PDF).
- **Save** as SVG (⌘S), PDF (⌘D), or PNG (⌘E); remembers the last folder.
- **Color**: inherit / black / any CSS color, with a native color well.
- **Scaling**: default (1 ex = 8 px), match a CSS font, or manual px-per-ex.
- **Display mode** toggle, **SVG source** view (⌘U), transparent-background PNG at
  96–600 dpi.
- **History** (⇧⌘H): equations you've exported, restorable with their settings.
  Hidden by default.
- **Macro preamble**: a persistent `\newcommand` block applied to every render.

## Layout

| Path | Role |
|---|---|
| `Sources/LatexCore` | Pure logic: settings, SVG post-processing, history/preamble stores. All unit tests target this. |
| `Sources/LatexRender` | The MathJax engine (offscreen `WKWebView`) and the SVG→PDF→PNG export pipeline. `Resources/render.html` is the entire JS surface. |
| `Sources/LatexToSVG` | The SwiftUI app. |
| `Scripts/bundle.sh` | Assembles the `.app` from SwiftPM output (SwiftPM alone emits a bare executable, and WebKit requires a signed bundle). |

Data lives in `~/Library/Application Support/LatexToSVG/` (`history.json`,
`preamble.tex`) — both plain text.

## Updating MathJax

Replace `Sources/LatexRender/Resources/mathjax/tex-svg.js` with a newer
`mathjax@N/tex-svg.js` from npm and rebuild. It's a single self-contained file.
