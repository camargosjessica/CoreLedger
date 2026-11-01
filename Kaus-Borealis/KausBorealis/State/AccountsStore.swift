import Foundation
import Observation
import KausMedia

/// Contas e a posição consolidada (guardado, disponível, cartão).
@MainActor
@Observable
final class AccountsStore {
    private(set) var all: [AccountDTO] = []
    private(set) var position: FinancialPosition?

    @ObservationIgnored private let session: LedgerSession

    init(session: LedgerSession) {
        self.session = session
    }

    func reload() async {
        await session.run {
            let api = session.api
            async let accounts = api.accounts()
            async let position = api.position()
            self.all = try await accounts
            self.position = try await position
        }
    }

    func add(name: String, kind: AccountKind) async {
        await session.run { _ = try await session.api.createAccount(AccountDTO(name: name, kind: kind)) }
        await session.refresh(.accounts)
    }

    func update(_ account: AccountDTO) async {
        guard let id = account.id else { return }
        await session.run { _ = try await session.api.updateAccount(id: id, account) }
        await session.refresh(.accounts)
    }

    /// Apagar a conta apaga os lançamentos dela (cascade no banco).
    func delete(_ account: AccountDTO) async {
        guard let id = account.id else { return }
        await session.run { try await session.api.deleteAccount(id: id) }
        if session.selectedAccountID == id {
            session.coordinator?.selectedAccountID = nil
        }
        await session.refresh(.all)
    }

    /// Lançamentos de uma conta num mês, sem mexer nos filtros da aba Lançamentos.
    func transactions(of accountID: UUID, in month: YearMonth) async -> [TransactionDTO] {
        var loaded: [TransactionDTO] = []
        await session.run {
            loaded = try await session.api.transactions(
                TransactionQuery(
                    accountID: accountID,
                    from: month.startDate,
                    to: LedgerCalendar.addingDays(-1, to: month.adding(months: 1).startDate),
                    limit: 1000
                ))
        }
        return loaded.sorted { $0.date > $1.date }
    }
}
