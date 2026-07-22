import Foundation

/// One remembered equation.
///
/// Alongside the source, the finalized SVG is kept so the history list can show
/// the equation as it looked, without re-rendering. It is a few kilobytes of
/// text per entry, and the file stays hand-editable.
public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var latex: String
    public var settings: RenderSettings
    public var date: Date
    /// The finalized SVG at export time. Optional so entries from older
    /// versions of the file still decode.
    public var svg: String?

    public init(id: UUID = UUID(), latex: String, settings: RenderSettings,
                date: Date, svg: String? = nil) {
        self.id = id
        self.latex = latex
        self.settings = settings
        self.date = date
        self.svg = svg
    }
}

/// Where the application keeps its files.
public enum AppDirectories {
    public static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let directory = base.appendingPathComponent("LatexToSVG", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// A newest-first list of equations the user has exported.
///
/// Entries are recorded when an equation is copied, saved, or dragged out --
/// not on every render. With live preview running on each keystroke, recording
/// renders would fill the list with fragments like `\fra` and `\frac{`. Export
/// is the point at which the user has signalled the equation is finished.
public final class HistoryStore {
    /// Bounds the file so it cannot grow without limit over years of use.
    public static let capacity = 200

    private let fileURL: URL
    public private(set) var entries: [HistoryEntry] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.entries = Self.read(from: fileURL)
    }

    public convenience init() throws {
        self.init(fileURL: try AppDirectories.supportDirectory()
            .appendingPathComponent("history.json"))
    }

    /// Records an equation, moving it to the top if its source is already known.
    ///
    /// Deduplicating means repeatedly exporting the same equation while tuning
    /// its colour or scale leaves one entry rather than a dozen near-identical
    /// ones. The settings of the most recent export win.
    @discardableResult
    public func record(latex: String, settings: RenderSettings,
                       svg: String? = nil, date: Date = Date()) -> HistoryEntry? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        entries.removeAll { $0.latex == trimmed }
        let entry = HistoryEntry(latex: trimmed, settings: settings, date: date, svg: svg)
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
        write()
        return entry
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        write()
    }

    public func clear() {
        entries.removeAll()
        write()
    }

    private static func read(from url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        // A corrupt or hand-edited file must not prevent the app from starting.
        // Losing history is a far smaller harm than refusing to launch.
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// The global macro preamble, applied to every render.
public final class PreambleStore {
    private let fileURL: URL
    public var text: String {
        didSet { try? text.write(to: fileURL, atomically: true, encoding: .utf8) }
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    public convenience init() throws {
        self.init(fileURL: try AppDirectories.supportDirectory()
            .appendingPathComponent("preamble.tex"))
    }
}
