import Vapor

extension Parameters {
    /// Identificador da rota; `400 Identificador inválido` quando não é um UUID.
    func uuid(_ name: String) throws -> UUID {
        guard let id = get(name, as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador inválido")
        }
        return id
    }
}
