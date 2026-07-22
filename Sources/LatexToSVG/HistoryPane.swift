import LatexCore
import SwiftUI

/// The left-hand pane: equations the user has previously exported.
///
/// Hidden by default. It exists for people who reuse notation across a document
/// and would otherwise have no way back to an equation's source, since neither
/// SVG nor PDF records the TeX it came from.
struct HistoryPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.history.isEmpty {
                    Button("Clear", action: model.clearHistory)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if model.history.isEmpty {
                VStack(spacing: 6) {
                    Text("No equations yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Equations are remembered when you copy, save, or drag them out.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                List {
                    ForEach(model.history) { entry in
                        row(entry)
                            .contentShape(Rectangle())
                            .onTapGesture { model.restore(entry) }
                            .contextMenu {
                                Button("Restore") { model.restore(entry) }
                                Button("Delete", role: .destructive) {
                                    model.deleteHistoryEntry(id: entry.id)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 240)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = thumbnail(for: entry) {
                // Each thumbnail sits on its own paper chip, matching the main
                // sheet -- dark paper when the equation was exported in white.
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 44, alignment: .leading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(entry.settings.color == .white ? Theme.paperDark : Theme.paperLight))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.18)))
            } else {
                Text(entry.latex)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Text(entry.date, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .help(entry.latex)
    }

    /// macOS decodes SVG natively, so the stored markup becomes an image
    /// directly -- no web view and no separate thumbnail cache.
    private func thumbnail(for entry: HistoryEntry) -> NSImage? {
        guard let svg = entry.svg,
              let image = NSImage(data: Data(svg.utf8)),
              image.size.width > 0 else { return nil }
        return image
    }
}
