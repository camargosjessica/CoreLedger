import KausMedia
import SwiftUI

extension EnvironmentValues {
    /// Relógio das telas que destacam o mês corrente. A RootView injeta o
    /// mesmo da LedgerStore; previews e testes podem fixar uma data.
    @Entry var ledgerClock: LedgerClock = .system
}
