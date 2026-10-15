import Fluent
import KausMedia

/// Troca as tags por subcategorias: a primeira tag de cada lançamento, regra ou
/// compromisso vira "Categoria › Tag", e a tag "essencial" vira a chave
/// essencial da categoria-mãe.
struct ConvertTagsToSubcategoriesMigration: AsyncMigration {
    /// Tags que eram sugeridas automaticamente e não descrevem uma subcategoria.
    private static let automaticTags: Set<String> = [TagSet.essential, "variável", "reserva"]

    func prepare(on database: Database) async throws {
        var essentials: Set<String> = []

        for model in try await TransactionModel.query(on: database).all() where !model.tags.isEmpty {
            model.category = convert(model.category, tags: model.tags, essentials: &essentials)
            model.tags = []
            try await model.update(on: database)
        }
        for model in try await CategoryRuleModel.query(on: database).all() where !model.tags.isEmpty {
            model.category = convert(model.category, tags: model.tags, essentials: &essentials)
            model.tags = []
            try await model.update(on: database)
        }
        for model in try await RecurringCommitmentModel.query(on: database).all() where !model.tags.isEmpty {
            model.category = convert(model.category, tags: model.tags, essentials: &essentials)
            model.tags = []
            try await model.update(on: database)
        }

        for category in essentials {
            let exists = try await CategorySettingModel.query(on: database)
                .filter(\.$category == category)
                .count() > 0
            guard !exists else { continue }
            try await CategorySettingModel(setting: CategorySetting(category: category, isEssential: true))
                .create(on: database)
        }
    }

    func revert(on database: Database) async throws { }

    private func convert(_ category: String, tags: [String], essentials: inout Set<String>) -> String {
        let normalized = TagSet.normalize(tags)
        guard !category.isEmpty else { return category }
        if normalized.contains(TagSet.essential) {
            essentials.insert(CategoryPath.parent(of: category))
        }
        guard CategoryPath.child(of: category) == nil,
              let tag = normalized.first(where: { !Self.automaticTags.contains($0) }) else { return category }
        return CategoryPath.join(category, tag.prefix(1).uppercased() + tag.dropFirst())
    }
}
