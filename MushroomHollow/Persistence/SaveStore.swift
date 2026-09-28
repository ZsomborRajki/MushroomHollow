import Foundation
import GameCore
import SwiftData

/// One saved character. The full profile is a Codable blob (the same value the online
/// server will store later); a few fields are duplicated as columns for a character list.
@Model
final class SavedCharacter {
    var name: String
    var level: Int
    var profileData: Data
    var updatedAt: Date

    init(name: String, level: Int, profileData: Data, updatedAt: Date = .now) {
        self.name = name
        self.level = level
        self.profileData = profileData
        self.updatedAt = updatedAt
    }
}

/// Loads and saves the local character with SwiftData.
final class SaveStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: SavedCharacter.self, configurations: configuration)
        context = ModelContext(container)
    }

    func load() -> PlayerProfile? {
        guard let saved = try? context.fetch(FetchDescriptor<SavedCharacter>()).first else { return nil }
        return try? decoder.decode(PlayerProfile.self, from: saved.profileData)
    }

    func save(_ profile: PlayerProfile) {
        guard let data = try? encoder.encode(profile) else { return }
        if let existing = try? context.fetch(FetchDescriptor<SavedCharacter>()).first {
            existing.level = profile.level
            existing.profileData = data
            existing.updatedAt = .now
        } else {
            context.insert(SavedCharacter(name: "Sprout", level: profile.level, profileData: data))
        }
        try? context.save()
    }

    func deleteAll() {
        try? context.delete(model: SavedCharacter.self)
        try? context.save()
    }
}
