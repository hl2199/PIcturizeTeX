import LatexCore
import SwiftUI

@main
struct LatexToSVGApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .commands { commands }
    }

    /// Copy is deliberately not bound to Command-C. The equation editor is a
    /// normal text field, and stealing Command-C would stop the user copying
    /// their own LaTeX -- a worse loss than one extra modifier on export.
    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(after: .saveItem) {
            ForEach(ExportFormat.allCases, id: \.self) { format in
                Button("Save as \(format.displayName)…") {
                    Task { await model.save(format: format) }
                }
                .keyboardShortcut(shortcut(for: format), modifiers: .command)
                .disabled(model.renderedSVG == nil)
            }
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Equation") {
                Task { await model.copyToPasteboard() }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.renderedSVG == nil)
        }
    }

    private func shortcut(for format: ExportFormat) -> KeyEquivalent {
        switch format {
        case .svg: return "s"
        case .pdf: return "d"
        case .png: return "e"
        }
    }
}
