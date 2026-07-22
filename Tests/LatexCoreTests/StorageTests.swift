import Foundation
import Testing
@testable import LatexCore

/// Gives each test its own throwaway directory, so they cannot interfere.
private struct TempDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("latextosvg-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    deinit { try? FileManager.default.removeItem(at: url) }
}

@Suite("History store")
struct HistoryStoreTests {

    @Test("entries are listed newest first")
    func newestFirst() throws {
        let dir = try TempDirectory()
        let store = HistoryStore(fileURL: dir.file("history.json"))
        store.record(latex: "a", settings: RenderSettings())
        store.record(latex: "b", settings: RenderSettings())
        #expect(store.entries.map(\.latex) == ["b", "a"])
    }

    @Test("entries survive a round trip through disk")
    func roundTrip() throws {
        let dir = try TempDirectory()
        let settings = RenderSettings(displayMode: false, color: .custom("#ff0000"),
                                      scale: .manual(15))
        HistoryStore(fileURL: dir.file("history.json"))
            .record(latex: "e^{i\\pi}", settings: settings)

        let reloaded = HistoryStore(fileURL: dir.file("history.json"))
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries.first?.latex == "e^{i\\pi}")
        #expect(reloaded.entries.first?.settings == settings)
    }

    @Test("the rendered SVG is stored for thumbnails and survives reload")
    func storesSVG() throws {
        let dir = try TempDirectory()
        HistoryStore(fileURL: dir.file("history.json"))
            .record(latex: "x", settings: RenderSettings(), svg: "<svg>x</svg>")
        #expect(HistoryStore(fileURL: dir.file("history.json")).entries.first?.svg == "<svg>x</svg>")
    }

    @Test("a repeated source is deduplicated and promoted")
    func deduplicates() throws {
        // Re-exporting while tuning colour or scale should not accumulate near
        // duplicates; the entry moves to the top and adopts the newest settings.
        let dir = try TempDirectory()
        let store = HistoryStore(fileURL: dir.file("history.json"))
        store.record(latex: "a", settings: RenderSettings())
        store.record(latex: "b", settings: RenderSettings())
        store.record(latex: "a", settings: RenderSettings(displayMode: false))

        #expect(store.entries.map(\.latex) == ["a", "b"])
        #expect(store.entries.first?.settings.displayMode == false)
    }

    @Test("whitespace is trimmed and a blank source ignored")
    func trimsAndIgnoresBlank() throws {
        let dir = try TempDirectory()
        let store = HistoryStore(fileURL: dir.file("history.json"))
        #expect(store.record(latex: "   \n ", settings: RenderSettings()) == nil)
        store.record(latex: "  x  ", settings: RenderSettings())
        #expect(store.entries.map(\.latex) == ["x"])
    }

    @Test("the list is bounded")
    func capacityBounded() throws {
        let dir = try TempDirectory()
        let store = HistoryStore(fileURL: dir.file("history.json"))
        for i in 0..<(HistoryStore.capacity + 10) {
            store.record(latex: "eq\(i)", settings: RenderSettings())
        }
        #expect(store.entries.count == HistoryStore.capacity)
        #expect(store.entries.first?.latex == "eq\(HistoryStore.capacity + 9)")
    }

    @Test("entries can be deleted individually and in bulk")
    func deleteAndClear() throws {
        let dir = try TempDirectory()
        let store = HistoryStore(fileURL: dir.file("history.json"))
        let entry = try #require(store.record(latex: "a", settings: RenderSettings()))
        store.record(latex: "b", settings: RenderSettings())
        store.delete(id: entry.id)
        #expect(store.entries.map(\.latex) == ["b"])
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(HistoryStore(fileURL: dir.file("history.json")).entries.isEmpty)
    }

    @Test("a corrupt file degrades to empty history rather than failing")
    func corruptFileDegrades() throws {
        let dir = try TempDirectory()
        let url = dir.file("history.json")
        try "{ this is not json".write(to: url, atomically: true, encoding: .utf8)

        let store = HistoryStore(fileURL: url)
        #expect(store.entries.isEmpty)

        // And the store must still be usable afterwards.
        store.record(latex: "a", settings: RenderSettings())
        #expect(HistoryStore(fileURL: url).entries.map(\.latex) == ["a"])
    }
}

@Suite("Preamble store")
struct PreambleStoreTests {

    @Test("the preamble persists, and a missing file means empty")
    func persists() throws {
        let dir = try TempDirectory()
        let url = dir.file("preamble.tex")
        #expect(PreambleStore(fileURL: url).text == "",
                "a missing preamble file means an empty preamble, not a failure")

        let store = PreambleStore(fileURL: url)
        store.text = "\\newcommand{\\R}{\\mathbb{R}}"
        #expect(PreambleStore(fileURL: url).text == "\\newcommand{\\R}{\\mathbb{R}}")
    }
}
