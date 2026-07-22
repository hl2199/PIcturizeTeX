// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LatexToSVG",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic. No WebKit, no AppKit UI. All unit tests live here.
        .target(name: "LatexCore"),

        // The MathJax render engine and the export pipeline. Owns the bundled JS.
        .target(
            name: "LatexRender",
            dependencies: ["LatexCore"],
            resources: [.copy("Resources/mathjax"), .copy("Resources/render.html")]
        ),

        // The SwiftUI app.
        .executableTarget(name: "LatexToSVG", dependencies: ["LatexCore", "LatexRender"]),

        .testTarget(name: "LatexCoreTests", dependencies: ["LatexCore"]),

        // Diagnostic harness for the exporter's window hosting; not shipped.
        .executableTarget(name: "ExportProbe", dependencies: ["LatexCore", "LatexRender"]),

        // Generates Assets/AppIcon.icns from the app's own render engine; not shipped.
        .executableTarget(name: "IconGen", dependencies: ["LatexCore", "LatexRender"]),
    ]
)
