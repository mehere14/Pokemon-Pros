import Foundation

public enum UpstreamResource: String, CaseIterable, Sendable {
    case creature = "creature"
    case species = "species"
    case form = "form"
    case move = "move"
    case encounter = "encounter"
    case generation = "generation"
    case type = "type"
    case evolution = "evolution-chain"
    case cardSearch = "cards"
    case cardDetail = "card"
}

/// Endpoint adapters keep provider URL shapes out of the iOS target. Concrete
/// DTO decoding is supplied by each call site so this package remains provider
/// neutral and easy to fixture-test.
public struct LoaderUpstreamClient: Sendable {
    public let baseURL: URL
    public let http: LoaderHTTPClient

    public init(baseURL: URL, http: LoaderHTTPClient) { self.baseURL = baseURL; self.http = http }

    public func fetch<Value: Decodable>(_ resource: UpstreamResource, identifier: String, as type: Value.Type = Value.self) async throws -> Value {
        let url = baseURL.appendingPathComponent(resource.rawValue).appendingPathComponent(identifier)
        return try await http.get(LoaderHTTPRequest(url: url), as: type)
    }

    public func fetchCreature<Value: Decodable>(id: Int, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.creature, identifier: String(id), as: type) }
    public func fetchSpecies<Value: Decodable>(id: Int, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.species, identifier: String(id), as: type) }
    public func fetchForm<Value: Decodable>(id: Int, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.form, identifier: String(id), as: type) }
    public func fetchMove<Value: Decodable>(id: Int, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.move, identifier: String(id), as: type) }
    public func fetchEncounter<Value: Decodable>(id: Int, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.encounter, identifier: String(id), as: type) }
    public func fetchGeneration<Value: Decodable>(id: Int, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.generation, identifier: String(id), as: type) }
    public func fetchType<Value: Decodable>(id: Int, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.type, identifier: String(id), as: type) }
    public func fetchEvolution<Value: Decodable>(id: Int, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.evolution, identifier: String(id), as: type) }
    public func fetchCardDetail<Value: Decodable>(id: String, as type: Value.Type = Value.self) async throws -> Value { try await fetch(.cardDetail, identifier: id, as: type) }

    public func searchCards<Value: Decodable>(query: [URLQueryItem] = [], decodePage: @escaping @Sendable (Data) throws -> ([Value], String?)) async throws -> [Value] {
        try await http.fetchAll(baseURL: baseURL, path: UpstreamResource.cardSearch.rawValue, query: query, decodePage: decodePage)
    }
}
