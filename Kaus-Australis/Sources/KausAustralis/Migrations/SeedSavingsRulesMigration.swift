import Fluent
import KausMedia

/// Acrescenta as regras de caixinha/investimento a bancos que já rodaram o seed
/// original. Insere apenas o que falta, para não ressuscitar regras que o
/// usuário apagou de propósito nem duplicar as que ele mesmo criou.
struct SeedSavingsRulesMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        for rule in CategoryRule.savingsSeed {
            let existing = try await CategoryRuleModel.query(on: database)
                .filter(\.$term == rule.term)
                .filter(\.$category == rule.category)
                .filter(\.$amountScope == rule.amountScope.rawValue)
                .first()
            guard existing == nil else { continue }
            try await CategoryRuleModel(rule: rule).create(on: database)
        }
    }

    func revert(on database: Database) async throws {
        try await CategoryRuleModel.query(on: database)
            .filter(\.$term ~~ CategoryRule.savingsSeed.map(\.term))
            .filter(\.$category == "Guardado")
            .delete()
    }
}
