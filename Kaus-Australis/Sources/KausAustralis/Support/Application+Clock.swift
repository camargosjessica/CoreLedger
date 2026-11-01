import KausMedia
import Vapor

extension Application {
    private struct ClockKey: StorageKey {
        typealias Value = LedgerClock
    }

    /// Relógio usado pelas regras que dependem do mês corrente. Os testes
    /// trocam por `LedgerClock.fixed(_:)`.
    var ledgerClock: LedgerClock {
        get { storage[ClockKey.self] ?? .system }
        set { storage[ClockKey.self] = newValue }
    }
}

extension Request {
    var ledgerClock: LedgerClock { application.ledgerClock }
}
