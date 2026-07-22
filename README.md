<div align="center">

<img src="docs/icon.png" width="110" alt="PIcturizeTeX icon">

# PIcturizeTeX

**LaTeX equations → SVG · PDF · PNG, natively on your Mac.**

[![Release](https://img.shields.io/github/v/release/hl2199/PIcturizeTeX?color=2e6e5e)](../../releases)
![Platform](https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20Silicon-2e6e5e)
[![License: MIT](https://img.shields.io/badge/license-MIT-2e6e5e)](LICENSE)

</div>

A native Mac app that turns LaTeX equations into pictures — SVG, PDF, and PNG. For use in your figures, presentations, and whatever else you may need it for. Live preview, easy drag and drop, quick menu bar access, customizable color and size. Inspired by [viereck.ch/latex-to-svg](https://viereck.ch/latex-to-svg/), but I wanted to make it local. Also has quick menu bar option for generation on the go!

<img width="800" height="528" alt="PIcturizeTeX main window" src="https://github.com/user-attachments/assets/a090e9f4-8d2c-4fed-9fa5-f228fd6a62d7" />

<img width="779" height="542" alt="PIcturizeTeX menu bar companion" src="https://github.com/user-attachments/assets/79129ee4-d4e8-445b-a13d-7240fa91565d" />

## Features

- **Live preview** at the equation's true export size, rendered as you type
- **Drag the equation out** — straight into Keynote, PowerPoint, Illustrator, or Finder
- **Right-click to copy** PDF + PNG + SVG in one go; every app takes the format it understands best
- **Save** as SVG (⌘S), PDF (⌘D), or PNG (⌘E) — transparent PNGs at 96–600 dpi
- **Color and size** — black, white, or any custom color; scale by pixels, match a document font, or set it manually
- **History** of exported equations with rendered thumbnails, restorable with their settings
- **Macro preamble** — a persistent `\newcommand` block applied to every render
- **Fully offline** — equations are typeset by a bundled MathJax 4

## Install

Download the latest `PIcturizeTeX-x.y.z.zip` from
[Releases](../../releases), unzip it, and drag `PIcturizeTeX.app` into
`/Applications`.

Binary requires macOS 14 or later on Apple Silicon. Intel Macs: build from source.

**First launch:** this build is not notarized (no Apple Developer account), so on a first
run, macOS will raise a security warning and the app must be approved once by hand.

<details>
<summary><strong>Step-by-step: approving the app on first launch</strong></summary>

1. Open the app. A dialog appears saying *"Apple could not verify 'PIcturizeTeX'
   is free of malware that may harm your Mac or compromise your privacy"*,
   offering only **Done** and **Move to Trash**. Click **Done** (not Move to
   Trash — that deletes the app).
2. Open **System Settings → Privacy & Security** and scroll down to the
   Security section. It says *"PIcturizeTeX" was blocked to protect your Mac*.
   Click **Open Anyway** and authenticate. (The message only lingers for a few
   minutes after the blocked attempt — if it is missing, open the app again
   and come straight back.)
3. Open the app once more. This time the dialog has an **Open** button — click it.

That's needed exactly once; afterwards the app opens normally.

</details>

If you would rather not trust a downloaded binary, build it from source below —
it takes about a minute and skips all of the above.

### Build from source

Requires only the Xcode Command Line Tools (no Xcode):

```sh
./Scripts/bundle.sh            # builds and assembles build/PIcturizeTeX.app
open build/PIcturizeTeX.app
```

Release build: `./Scripts/bundle.sh release` · Tests: `swift test` ·
Release zip: `./Scripts/release.sh <version>`

## Under the hood

| Path | Role |
|---|---|
| `Sources/LatexCore` | Pure logic: settings, SVG post-processing, history/preamble stores. All unit tests target this. |
| `Sources/LatexRender` | The MathJax engine (offscreen `WKWebView`) and the SVG→PDF→PNG export pipeline. `Resources/render.html` is the entire JS surface. |
| `Sources/LatexToSVG` | The SwiftUI app. |
| `Scripts/bundle.sh` | Assembles the `.app` from SwiftPM output (SwiftPM alone emits a bare executable, and WebKit requires a signed bundle). |

Data lives in `~/Library/Application Support/PIcturizeTeX/` (`history.json`,
`preamble.tex`) — both plain text.

To update MathJax, replace `Sources/LatexRender/Resources/mathjax/tex-svg.js`
with a newer `mathjax@N/tex-svg.js` from npm and rebuild — it's a single
self-contained file.

## License

MIT — see [LICENSE](LICENSE). Equations are typeset by
[MathJax](https://www.mathjax.org), which is bundled under the Apache License
2.0 (`Sources/LatexRender/Resources/mathjax/LICENSE`).
