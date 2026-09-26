import Foundation

/// Consolidação de um mês.
public struct MonthlySummary: Codable, Sendable, Hashable, Identifiable {
    /// Primeiro dia do mês, em UTC.
    public var month: Date
    public var income: Double
    public var expenses: Double
    public var byCategory: [String: Double]
    /// `true` quando o mês é estimado (média histórica) em vez de realizado.
    public var isForecast: Bool
    /// Parcelas futuras já contratadas que caem neste mês.
    public var committedExpenses: Double

    public var id: Date { month }
    public var balance: Double { income + expenses }

    public init(
        month: Date,
        income: Double = 0,
        expenses: Double = 0,
        byCategory: [String: Double] = [:],
        isForecast: Bool = false,
        committedExpenses: Double = 0
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
