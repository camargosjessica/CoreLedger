import Foundation

/// Calendário e fusos usados por todo o domínio.
///
/// O servidor grava datas em UTC. Se o agrupamento mensal usar o calendário do
/// dispositivo, um lançamento do dia 1º às 00h30 UTC cai no mês anterior para quem
/// está em `America/Sao_Paulo`. Por isso todas as operações de data passam por aqui.
public enum LedgerCalendar {
    public static let timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Meia-noite UTC do dia da data. Extratos trazem data sem hora; guardar o
    /// instante bruto faria o mesmo lançamento gerar chaves diferentes.
    public static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func startOfMonth(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? startOfDay(date)
    }

    public static func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public static func addingMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// Formatador ISO (`yyyy-MM-dd`) em UTC, para chaves estáveis.
    public static func isoDay(_ date: Date) -> String {
        isoDayFormatter.string(from: date)
    }

    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Double {
    /// Valor em centavos, para comparações exatas (chave de deduplicação, somas de parcelas).
    public var centsValue: Int {
        Int((self * 100).rounded())
    }
}
