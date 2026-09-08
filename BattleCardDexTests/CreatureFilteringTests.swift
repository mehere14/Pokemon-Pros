import Testing
@testable import Battle_Card_Dex

@Test("filtering handles names, numbers, generation, and types")
func filtering() {
    let entries = [
        CreatureSummary(id: 1, name: "alpha", displayName: "Alpha", generation: "generation-1", types: ["leaf"], artworkURL: nil),
        CreatureSummary(id: 2, name: "beta", displayName: "Béta", generation: "generation-1", types: ["water"], artworkURL: nil),
        CreatureSummary(id: 20, name: "gamma", displayName: "Gamma", generation: "generation-2", types: ["leaf"], artworkURL: nil)
    ]
    #expect(CreatureFilter(query: "beta").apply(to: entries).map(\.id) == [2])
    #expect(CreatureFilter(query: "2").apply(to: entries).map(\.id) == [2, 20])
    #expect(CreatureFilter(query: "beta").apply(to: entries).map(\.id) == [2])
    #expect(CreatureFilter(generation: "generation-2", type: "leaf").apply(to: entries).map(\.id) == [20])
}

@Test("surprise order genuinely shuffles only the filtered set")
func surpriseOrder() {
    let entries = (1...6).map { CreatureSummary(id: $0, name: "c\($0)", displayName: "C\($0)", generation: nil, types: [], artworkURL: nil) }
    let filter = CreatureFilter(query: "")
    let first = filter.surpriseOrder(entries, seed: 17)
    let repeated = filter.surpriseOrder(entries, seed: 17)
    let second = filter.surpriseOrder(entries, seed: 18)
    #expect(first == repeated)
    #expect(first != entries)
    #expect(first != second)
    #expect(Set(first) == Set(entries))
}
