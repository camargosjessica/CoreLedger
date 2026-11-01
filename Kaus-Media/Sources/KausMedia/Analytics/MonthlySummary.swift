import Foundation

/// Consolidação de um mês.
public struct MonthlySummary: Codable, Sendable, Hashable, Identifiable {
    /// Primeiro dia do mês, em UTC.
    public var month: Date
    public var income: Money
    public var expenses: Money
    public var byCategory: [String: Money]
    /// `true` para meses à frente, que só somam lançamentos futuros e parcelas.
    public var isForecast: Bool
    /// Parcelas futuras já contratadas que caem neste mês.
    public var committedExpenses: Money

    public var id: Date { month }
    public var balance: Money { income + expenses }

    public init(
        month: Date,
        income: Money = 0,
        expenses: Money = 0,
        byCategory: [String: Money] = [:],
        isForecast: Bool = false,
        committedExpenses: Money = 0
    ) {
        self.month = month
        self.income = income
        self.expenses = expenses
        self.byCategory = byCategory
        self.isForecast = isForecast
        self.committedExpenses = committedExpenses
    }
}

/// Histórico realizado + previsão dos próximos meses.
public struct LedgerProjection: Codable, Sendable {
    public var history: [MonthlySummary]
    public var forecast: [MonthlySummary]

    public init(history: [MonthlySummary], forecast: [MonthlySummary]) {
        self.history = history
        self.forecast = forecast
    }

    public var all: [MonthlySummary] { history + forecast }
}
