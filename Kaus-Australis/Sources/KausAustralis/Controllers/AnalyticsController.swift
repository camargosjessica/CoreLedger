import Fluent
import Vapor
import KausMedia

/// Para onde foi o dinheiro: gastos do ano por categoria ou tag, mês a mês.
struct AnalyticsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("api", "analytics", "spending", use: spending)
    }

    func spending(req: Request) async throws -> SpendingReport {
        let query = try req.query.decode(SpendingQuery.self)
        let year = query.year ?? YearMonth(date: Date()).year
        guard (1...9998).contains(year) else {
            throw Abort(.badRequest, reason: "Ano inválido")
        }
        let grouping = query.groupBy ?? .category

        var builder = TransactionModel.query(on: req.db)
            .filter(\.$date >= YearMonth(year: year, month: 1).startDate)
            .filter(\.$date < YearMonth(year: year + 1, month: 1).startDate)
            .filter(\.$transferSource.$id == nil)
        if let accountID = query.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        } else if let kind = query.accountKind {
            let ids = try await AccountModel.query(on: req.db)
                .filter(\.$kind == kind.rawValue)
                .all()
                .compactMap(\.id)
            builder = builder.filter(\.$account.$id ~~ ids)
        }
        let transactions = try await builder.all()

        // Aportes em caixinha e transferências não são gasto: o dinheiro só mudou de lugar.
        let savingCategories = try await RecurringCommitmentModel.query(on: req.db).all()
            .map { $0.toDTO() }
            .filter { $0.kind == .saving }
            .map(\.category)
        let excluded = try await req.categoryRules.categorizer().transferCategories
            .union(savingCategories)
            .union(["Guardado"])

        return SpendingAnalysis.make(
            transactions.map {
                SpendingAnalysis.Input(
                    date: $0.date,
                    amount: $0.amount,
                    category: $0.category,
                    tags: $0.tags,
                    isProjected: $0.isProjected
                )
            },
            year: year,
            grouping: grouping,
            excludedCategories: excluded
        )
    }
}

struct SpendingQuery: Content {
    var year: Int?
    var groupBy: SpendingGrouping?
    var accountID: UUID?
    /// Sem `accountID`, restringe às contas deste tipo (ex.: todos os cartões).
    var accountKind: AccountKind?
}
