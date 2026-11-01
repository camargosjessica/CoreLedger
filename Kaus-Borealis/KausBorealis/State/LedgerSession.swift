import Foundation
import Observation

/// Estado compartilhado pelas stores de feature: conexão, conta em foco e o
/// resultado das operações (erro, carregando, alcançável).
@MainActor
@Observable
final class LedgerSession {
    var configuration: APIConfiguration
    /// Conta selecionada nos filtros; `nil` significa todas.
    var selectedAccountID: UUID?

    var errorMessage: String?
    var isLoading = false
    /// Resultado da última carga completa, para o indicador de conexão.
    var isReachable = true
    /// Muda a cada recarga de lançamentos, para telas com dados próprios
    /// (Análise) recarregarem.
    private(set) var dataGeneration = 0

    /// Recargas em lote em andamento: dentro delas, o sucesso de uma parte
    /// não apaga o erro de outra que rodou em paralelo.
    @ObservationIgnored var batchDepth = 0

    @ObservationIgnored private let makeAPI: (APIConfiguration) -> any LedgerAPI
    /// Quem sabe recarregar o que uma mudança invalidou. Fraca: o coordenador
    /// é dono da sessão.
    @ObservationIgnored weak var coordinator: LedgerStore?

    init(configuration: APIConfiguration, makeAPI: @escaping (APIConfiguration) -> any LedgerAPI) {
        self.configuration = configuration
        self.makeAPI = makeAPI
    }

    var api: any LedgerAPI { makeAPI(configuration) }

    /// Recarrega o que `scope` cobre depois de uma mudança.
    func refresh(_ scope: LedgerStore.Scope) async {
        await coordinator?.reload(scope)
    }

    func didReloadTransactions() {
        dataGeneration += 1
    }

    /// Executa a operação e registra o erro para o alerta global.
    /// Cancelamentos (troca rápida de filtro) não são erro.
    /// - Returns: `true` quando terminou sem erro.
    @discardableResult
    func run(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            if batchDepth == 0 { errorMessage = nil }
            return true
        } catch {
            if Self.isCancellation(error) || Task.isCancelled { return false }
            errorMessage = Self.message(for: error)
            return false
        }
    }

    static func message(for error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? URLError, error.code == .cancelled { return true }
        if case let .transport(underlying) = error as? APIError { return isCancellation(underlying) }
        return false
    }
}
