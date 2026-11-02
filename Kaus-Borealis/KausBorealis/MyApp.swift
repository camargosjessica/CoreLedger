import KausMedia
import SwiftUI

@main
struct MyApp: App {
    @State private var store = CompositionRoot.makeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.ledgerClock, store.clock)
        }
    }
}

/// O único lugar que decide as implementações concretas: qual backend, qual
/// relógio, de onde vem a configuração. As telas e as stores só conhecem as
/// abstrações (LedgerStore, LedgerAPI, LedgerClock).
enum CompositionRoot {
    /// O app também é o host dos testes de unidade; nesse caso ele não deve
    /// falar com o servidor local nem ler o Keychain.
    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func makeStore() -> LedgerStore {
        #if DEBUG
            if isHostingTests {
                return .preview()
            }
        #endif
        return LedgerStore(configuration: .load(), clock: .system) { configuration in
            APIClient(configuration: configuration)
        }
    }
}
