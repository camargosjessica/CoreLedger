import Fluent
import Vapor

extension Parameters {
    /// Identificador da rota; `400 Identificador inválido` quando não é um UUID.
    func uuid(_ name: String) throws -> UUID {
        guard let id = get(name, as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador inválido")
        }
        return id
    }

    /// Nome (categoria, tag) na rota; vazio é `invalid`.
    func label(_ name: String, invalid: LedgerError) throws -> String {
        guard let value = get(name), !value.isEmpty else { throw invalid }
        return value
    }
}

extension Model where IDValue == UUID {
    /// O registro com `id`, ou `notFound` quando não existe.
    static func find(_ id: UUID, on database: any Database, or notFound: LedgerError) async throws -> Self {
        guard let model = try await find(id, on: database) else { throw notFound }
        return model
    }
}
