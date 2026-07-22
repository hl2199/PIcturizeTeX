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
    ]
)
