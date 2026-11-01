import Foundation

/// Fonte do "agora". Regras que dependem do mês corrente (o que é previsão,
/// qual mês destacar) recebem o relógio em vez de chamar `Date()`, para que
/// os testes fixem a data e não quebrem na virada do mês.
public struct LedgerClock: Sendable {
    private let source: @Sendable () -> Date

    public init(_ source: @escaping @Sendable () -> Date) {
        self.source = source
    }

    public func now() -> Date { source() }

    /// Hoje, à meia-noite no calendário do ledger (UTC).
    public func today() -> Date { LedgerCalendar.startOfDay(now()) }

    public func currentMonth() -> YearMonth { YearMonth(date: now()) }

    /// Relógio do sistema.
    public static let system = LedgerClock { Date() }

    /// Relógio parado numa data, para testes e previews.
    public static func fixed(_ date: Date) -> LedgerClock {
        LedgerClock { date }
    }
}
