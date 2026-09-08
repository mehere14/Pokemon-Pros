import Foundation

struct CreatureFilter: Equatable, Sendable {
    var query: String = ""
    var generation: String? = nil
    var type: String? = nil

    func apply(to creatures: [CreatureSummary]) -> [CreatureSummary] {
        let token = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return creatures.filter { creature in
            let name = creature.displayName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let normalized = creature.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let matchesQuery = token.isEmpty || name.contains(token) || normalized.contains(token) || String(creature.id).contains(token)
            let matchesGeneration = generation == nil || creature.generation?.caseInsensitiveCompare(generation!) == .orderedSame
            let matchesType = type == nil || creature.types.contains { $0.caseInsensitiveCompare(type!) == .orderedSame }
            return matchesQuery && matchesGeneration && matchesType
        }.sorted { $0.id < $1.id }
    }

    func surpriseOrder(_ creatures: [CreatureSummary], seed: UInt64) -> [CreatureSummary] {
        var generator = SurpriseRandomNumberGenerator(seed: seed)
        return apply(to: creatures).shuffled(using: &generator)
    }
}

private struct SurpriseRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
