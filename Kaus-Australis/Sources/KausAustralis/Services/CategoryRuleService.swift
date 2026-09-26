import Fluent
import Vapor
import KausMedia

/// Monta o categorizador a partir das regras cadastradas.
struct CategoryRuleService {
    let database: any Database

    func rules() async throws -> [CategoryRule] {
        try await CategoryRuleModel.query(on: database)
            .sort(\.$priority)
            .all()
            .map { $0.toDTO() }
    }

    func categorizer() async throws -> Categorizer {
        Categorizer(rules: try await rules())
    }
}

extension Request {
    var categoryRules: CategoryRuleService { CategoryRuleService(database: db) }
}
