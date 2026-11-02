import Foundation
import Observation
import KausMedia

/// Regras de categorização e o catálogo de categorias e tags.
@MainActor
@Observable
final class RulesStore {
    private(set) var all: [CategoryRule] = []
    /// Categorias em uso no servidor, inclusive as digitadas direto num lançamento.
    private(set) var catalog: [String] = []

    @ObservationIgnored private let session: LedgerSession
    /// Filtros da lista que precisam acompanhar renomeações e exclusões.
    @ObservationIgnored private let transactions: TransactionsStore

    init(session: LedgerSession, transactions: TransactionsStore) {
        self.session = session
        self.transactions = transactions
    }

    func reload() async {
        await session.run {
            let api = session.api
            async let rules = api.categoryRules()
            async let catalog = api.categories()
            self.all = try await rules
            self.catalog = try await catalog
        }
    }

    func save(_ rule: CategoryRule) async {
        await session.run {
            if let id = rule.id {
                _ = try await session.api.updateRule(id: id, rule)
            } else {
                _ = try await session.api.createRule(rule)
            }
        }
        // As tags das regras aparecem na grade do plano.
        await session.refresh([.rules, .plan])
    }

    func delete(_ rule: CategoryRule) async {
        guard let id = rule.id else { return }
        await session.run { try await session.api.deleteRule(id: id) }
        await session.refresh([.rules, .plan])
    }

    func preview(description: String, amount: Money, rule: CategoryRule?) async -> CategoryPreviewResponse? {
        var response: CategoryPreviewResponse?
        await session.run {
            response = try await session.api.preview(
                CategoryPreviewRequest(description: description, amount: amount, rule: rule)
            )
        }
        return response
    }

    /// Reaplica as regras ao histórico — sem isso, uma regra nova só valeria
    /// para lançamentos futuros.
    func recategorize(onlyUncategorized: Bool) async -> Int? {
        var updated: Int?
        await session.run {
            updated = try await session.api.recategorize(
                accountID: session.selectedAccountID,
                onlyUncategorized: onlyUncategorized
            ).updated
        }
        await session.refresh(.labels)
        return updated
    }

    // MARK: Categorias e tags

    /// Apaga a categoria inteira: as regras que a produzem somem e os
    /// lançamentos que a usavam voltam a passar pelas regras restantes.
    func deleteCategory(_ name: String) async -> DeleteCategoryResponse? {
        var response: DeleteCategoryResponse?
        await session.run { response = try await session.api.deleteCategory(name) }
        if transactions.selectedCategory == name { transactions.selectedCategory = nil }
        await session.refresh(.labels)
        return response
    }

    func renameCategory(_ name: String, to newName: String) async -> LabelChangeResponse? {
        var response: LabelChangeResponse?
        await session.run { response = try await session.api.renameCategory(name, to: newName) }
        if response != nil, transactions.selectedCategory == name { transactions.selectedCategory = newName }
        await session.refresh(.labels)
        return response
    }

    func renameTag(_ tag: String, to newName: String) async -> LabelChangeResponse? {
        var response: LabelChangeResponse?
        await session.run { response = try await session.api.renameTag(tag, to: newName) }
        if response != nil, transactions.selectedTag == tag {
            transactions.selectedTag = TagSet.normalize([newName]).first
        }
        await session.refresh(.labels)
        return response
    }

    func deleteTag(_ tag: String) async -> LabelChangeResponse? {
        var response: LabelChangeResponse?
        await session.run { response = try await session.api.deleteTag(tag) }
        if transactions.selectedTag == tag { transactions.selectedTag = nil }
        await session.refresh(.labels)
        return response
    }
}
