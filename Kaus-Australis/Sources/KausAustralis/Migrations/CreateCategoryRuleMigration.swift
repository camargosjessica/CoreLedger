import Fluent
import KausMedia

struct CreateCategoryRuleMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("category_rules")
            .id()
            .field("term", .string, .required)
            .field("category", .string, .required)
            .field("match_kind", .string, .required)
            .field("amount_scope", .string, .required)
            .field("priority", .int, .required)
            .field("is_enabled", .bool, .required)
            .field("is_transfer", .bool, .required)
            .field("created_at", .datetime)
            .unique(on: "term", "category", "amount_scope")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("category_rules").delete()
    }
}

/// Carga inicial das regras. A partir daqui a lista é editável pelo usuário —
/// o seed roda uma única vez e não sobrescreve alterações posteriores.
struct SeedCategoryRulesMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        let existing = try await CategoryRuleModel.query(on: database).count()
        guard existing == 0 else { return }

        for rule in CategoryRule.seed {
            try await CategoryRuleModel(rule: rule).create(on: database)
        }
    }

    func revert(on database: Database) async throws {
        let seedTerms = Set(CategoryRule.seed.map(\.term))
        try await CategoryRuleModel.query(on: database)
            .filter(\.$term ~~ Array(seedTerms))
            .delete()
    }
}
