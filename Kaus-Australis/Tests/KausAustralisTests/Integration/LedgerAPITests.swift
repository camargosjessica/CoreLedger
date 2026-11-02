import Foundation
import KausMedia
import Testing
import Vapor
import VaporTesting
@testable import KausAustralis

@Suite("API contra Postgres", .serialized, .enabled(if: Integration.isEnabled))
struct LedgerAPITests {
    @Test("Saldos, contagens e posição somados no banco")
    func balancesAreAggregatedInSQL() async throws {
        try await Integration.withApp { app in
            let checking = try await app.createAccount("Corrente", kind: .checking)
            let card = try await app.createAccount("Cartão", kind: .creditCard)
            try await app.createTransaction("Salário", 1000.10, on: "05/01/2026", account: checking)
            try await app.createTransaction("Padaria", -0.10, on: "06/01/2026", account: checking)
            try await app.createTransaction("Mercado", -200.20, on: "07/01/2026", account: card)
            try await app.createTransaction("Parcela 2/3", -50, on: "07/02/2099", account: card, projected: true)

            let accounts = try await app.get("api/accounts").content.decode([AccountDTO].self)
            let byName = Dictionary(uniqueKeysWithValues: accounts.map { ($0.name, $0) })
            #expect(byName["Corrente"]?.balance == 1000)
            #expect(byName["Corrente"]?.transactionCount == 2)
            #expect(byName["Cartão"]?.balance == -200.20, "A parcela prevista não entra no saldo")
            #expect(byName["Cartão"]?.transactionCount == 2)

            let position = try await app.get("api/position").content.decode(FinancialPosition.self)
            #expect(position.available == 1000)
            #expect(position.creditCardDebt == 200.20)
            #expect(position.upcomingInstallments == 50)
        }
    }

    @Test("Importar, reimportar sem duplicar e desfazer")
    func importIsIdempotentAndUndoable() async throws {
        try await Integration.withApp { app in
            let account = try await app.createAccount("Corrente", kind: .checking)
            let csv = """
            Data;Histórico;Valor
            15/01/2026;SUPERMERCADO BOM PRECO;-1.234,56
            16/01/2026;SALARIO JANEIRO;4.200,00
            """
            let request = ImportRequestDTO(accountID: account, filename: "extrato.csv", content: csv)

            let first = try await app.post("api/imports", request).content.decode(ImportReportDTO.self)
            #expect(first.imported == 2)
            #expect(first.failures.isEmpty)

            let second = try await app.post("api/imports", request).content.decode(ImportReportDTO.self)
            #expect(second.imported == 0)
            #expect(second.duplicates == 2)

            let batches = try await app.get("api/imports").content.decode([ImportBatchDTO].self)
            #expect(batches.map(\.transactionCount).sorted() == [0, 2])

            let batchID = try #require(first.batchID)
            let undo = try await app.delete("api/imports/\(batchID)").content.decode(BulkDeleteResponse.self)
            #expect(undo.deleted == 2)
            let left = try await app.get("api/transactions").content.decode([TransactionDTO].self)
            #expect(left.isEmpty)
        }
    }

    @Test("Transferência cria a contrapartida e some do resumo consolidado")
    func transferCounterpartIsMirroredAndExcludedFromSummary() async throws {
        try await Integration.withApp { app in
            let checking = try await app.createAccount("Corrente", kind: .checking)
            let savings = try await app.createAccount("Caixinha", kind: .savings)
            let origin = try await app.createTransaction("Aplicação", -300, on: "10/01/2026", account: checking)
            let id = try #require(origin.id)

            let linked = try await app.put("api/transactions/\(id)/transfer", TransferLinkRequest(accountID: savings))
            #expect(linked.status == .ok)
            #expect(try linked.content.decode(TransactionDTO.self).transferAccountID == savings)

            let inSavings = try await app.get("api/transactions?accountID=\(savings)").content.decode([TransactionDTO].self)
            #expect(inSavings.map(\.amount) == [300])
            #expect(inSavings.first?.transferSourceID == id)

            let editCounterpart = try await app.put("api/transactions/\(try #require(inSavings.first?.id))", inSavings[0])
            #expect(editCounterpart.status == .badRequest)

            let summary = try await app.get("api/summary?includeTransfers=true").content.decode(LedgerProjection.self)
            #expect(summary.history.map(\.expenses) == [-300], "A contrapartida não anula a origem no consolidado")
        }
    }

    @Test("Edição que colide com outro lançamento devolve 409")
    func duplicateEditIsAConflict() async throws {
        try await Integration.withApp { app in
            let account = try await app.createAccount("Corrente", kind: .checking)
            let first = try await app.createTransaction("Padaria", -10, on: "10/01/2026", account: account)
            var second = try await app.createTransaction("Padaria", -12, on: "10/01/2026", account: account)
            second.amount = first.amount

            let response = try await app.put("api/transactions/\(try #require(second.id))", second)

            #expect(response.status == .conflict)
            #expect(response.body.string.contains("Já existe um lançamento igual"))
        }
    }

    @Test("Busca ignora acentos e maiúsculas")
    func searchIsAccentInsensitive() async throws {
        try await Integration.withApp { app in
            try await app.createTransaction("FARMÁCIA SÃO JOÃO", -20, on: "10/01/2026", account: nil)
            try await app.createTransaction("Padaria", -5, on: "10/01/2026", account: nil)

            let found = try await app.get("api/transactions?search=farmacia%20sao").content.decode([TransactionDTO].self)

            #expect(found.map(\.description) == ["FARMÁCIA SÃO JOÃO"])
        }
    }

    @Test("Com API_TOKEN, as rotas exigem Bearer")
    func tokenIsRequiredWhenConfigured() async throws {
        try await Integration.withApp(environment: ["API_TOKEN": "segredo"]) { app in
            #expect(try await app.get("api/accounts").status == .unauthorized)

            let authorized = try await app.testing().sendRequest(.GET, "api/accounts") {
                $0.headers.bearerAuthorization = BearerAuthorization(token: "segredo")
            }
            #expect(authorized.status == .ok)
        }
    }
}
