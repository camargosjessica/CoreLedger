import Foundation
import Observation
import KausMedia

/// Grade anual, compromissos recorrentes, limites e categorias essenciais.
@MainActor
@Observable
final class PlanStore {
    private(set) var annual: AnnualPlan?
    private(set) var commitments: [RecurringCommitment] = []
    private(set) var knownTags: [String] = []
    private(set) var limits: [CategoryLimit] = []
    private(set) var categorySettings: [CategorySetting] = []

    /// Ano exibido na grade anual, no formato da planilha (janeiro a dezembro).
    var year: Int {
        didSet { if year != oldValue { scheduleGridReload() } }
    }

    @ObservationIgnored private var gridTask: Task<Void, Never>?
    @ObservationIgnored private let session: LedgerSession

    init(session: LedgerSession) {
        self.session = session
        self.year = session.clock.currentMonth().year
    }

    private var start: YearMonth { YearMonth(year: year, month: 1) }
    private var end: YearMonth { YearMonth(year: year, month: 12) }

    /// Grade, limites e preferências de categoria.
    func reload() async {
        await session.run {
            let api = session.api
            async let limits = api.limits()
            async let settings = api.categorySettings()
            self.limits = try await limits
            self.categorySettings = try await settings
        }
        await reloadGrid()
    }

    /// Só a grade anual (e os compromissos que vêm com ela).
    /// Só retorna quando a consulta mais recente terminou.
    func reloadGrid() async {
        scheduleGridReload()
        await TransactionsStore.awaitLatest { self.gridTask }
    }

    private func scheduleGridReload() {
        gridTask?.cancel()
        gridTask = Task { await fetchGrid() }
    }

    private func fetchGrid() async {
        let start = start, end = end
        await session.run {
            let response = try await session.api.plan(from: start, to: end, openingBalance: nil)
            try Task.checkCancellation()
            self.annual = response.plan
            self.commitments = response.commitments
            self.knownTags = response.knownTags
        }
    }

    // MARK: Compromissos

    func saveCommitment(_ commitment: RecurringCommitment) async {
        await session.run {
            if let id = commitment.id {
                _ = try await session.api.updateCommitment(id: id, commitment)
            } else {
                _ = try await session.api.createCommitment(commitment)
            }
        }
        await reloadGrid()
    }

    func deleteCommitment(_ commitment: RecurringCommitment) async {
        guard let id = commitment.id else { return }
        await session.run { try await session.api.deleteCommitment(id: id) }
        await reloadGrid()
    }

    // MARK: Limites

    func limit(for category: String) -> Money? {
        limits.first { $0.category == category }?.monthlyLimit
    }

    /// Valor `nil` ou zero remove o limite da categoria.
    func setLimit(_ monthlyLimit: Money?, for category: String) async {
        await session.run {
            let api = session.api
            if let monthlyLimit, monthlyLimit > 0 {
                _ = try await api.saveLimit(CategoryLimit(category: category, monthlyLimit: monthlyLimit))
            } else {
                try await api.deleteLimit(category: category)
            }
            self.limits = try await api.limits()
        }
    }

    // MARK: Essenciais

    /// Só a marcação da própria categoria, sem herdar da categoria-mãe.
    func isEssential(_ category: String) -> Bool {
        categorySettings.contains { $0.category == category && $0.isEssential }
    }

    func setEssential(_ isEssential: Bool, for category: String) async {
        await session.run {
            let api = session.api
            _ = try await api.saveCategorySetting(CategorySetting(category: category, isEssential: isEssential))
            self.categorySettings = try await api.categorySettings()
        }
        await reloadGrid()
    }
}
