import Vapor

/// Exige `Authorization: Bearer <API_TOKEN>` nas rotas financeiras.
///
/// Em desenvolvimento o servidor sobe sem token (o app fala com `localhost`);
/// fora de desenvolvimento `API_TOKEN` é obrigatório e a falta dele impede o
/// arranque, para que uma instância exposta nunca fique aberta por omissão.
struct APITokenMiddleware: AsyncMiddleware {
    let token: String

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let provided = request.headers.bearerAuthorization?.token,
              constantTimeEquals(provided, token)
        else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: request)
    }

    /// Comparação sem atalho no primeiro byte diferente.
    private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
