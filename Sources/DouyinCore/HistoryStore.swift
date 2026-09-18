import Foundation

public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var note: String
    public init(id: String, note: String = "") { self.id = id; self.note = note }
}

/// Persists only room IDs and user notes, never signed playback URLs.
public struct HistoryStore {
    private let defaults: UserDefaults
    private let key = "roomHistory.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> [HistoryEntry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
        var seen = Set<String>()
        return entries.filter { isID($0.id) && seen.insert($0.id).inserted }
    }
    public func record(_ id: String) -> [HistoryEntry] {
        var entries = load()
        guard isID(id) else { return entries }
        let entry = entries.first { $0.id == id } ?? HistoryEntry(id: id)
        entries.removeAll { $0.id == id }
        entries.insert(entry, at: 0)
        save(entries)
        return entries
    }
    public func setNote(_ note: String, for id: String) -> [HistoryEntry] {
        var entries = load()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return entries }
        entries[index].note = note
        save(entries)
        return entries
    }
    public func remove(_ id: String) -> [HistoryEntry] {
        let entries = load().filter { $0.id != id }
        save(entries)
        return entries
    }
    public func migrateLastInput(_ input: String) -> [HistoryEntry] {
        // Migrate once, so deleting the last item does not resurrect it on launch.
        if defaults.object(forKey: key) == nil {
            save([])
            if let id = try? LiveResolver.roomID(from: input) { return record(id) }
        }
        return load()
    }
    private func isID(_ value: String) -> Bool {
        value.range(of: #"^\d{5,25}$"#, options: .regularExpression) != nil
    }
    private func save(_ entries: [HistoryEntry]) {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }
}
