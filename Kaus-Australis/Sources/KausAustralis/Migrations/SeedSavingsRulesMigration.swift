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

    /// Remove só as linhas idênticas ao seed: uma regra que o usuário tenha
    /// ajustado (outro escopo, prioridade ou desligada) sobrevive ao rollback.
    func revert(on database: Database) async throws {
        for rule in CategoryRule.savingsSeed {
            try await CategoryRuleModel.query(on: database)
                .filter(\.$term == rule.term)
                .filter(\.$category == rule.category)
                .filter(\.$amountScope == rule.amountScope.rawValue)
                .filter(\.$matchKind == rule.matchKind.rawValue)
                .filter(\.$priority == rule.priority)
                .filter(\.$isTransfer == rule.isTransfer)
                .filter(\.$isEnabled == true)
                .delete()
        }
    }
}
