import Foundation

/// Corpo de `POST /api/imports`: conteúdo do extrato em texto.
public struct ImportRequestDTO: Codable, Sendable {
    public var accountID: UUID
    public var filename: String?
    public var content: String
    /// Sobrescreve a detecção automática pelo conteúdo/extensão.
    public var format: StatementFormat?
    /// Mês da fatura de cartão. Reenviar a fatura do mesmo cartão e mês
    /// substitui a importação anterior, levando tags, categoria e comentário
    /// das linhas que continuam na fatura.
    public var statementMonth: YearMonth?

    public init(
        accountID: UUID,
        filename: String? = nil,
        content: String,
        format: StatementFormat? = nil,
        statementMonth: YearMonth? = nil
    ) {
        self.accountID = accountID
        self.filename = filename
        self.content = content
        self.format = format
        self.statementMonth = statementMonth
    }
}

/// Resultado de uma importação, para exibição ao usuário.
public struct ImportReportDTO: Codable, Sendable {
    public var imported: Int
    /// Já existiam com a mesma chave e foram ignorados.
    public var duplicates: Int
    /// Lançamentos da fatura anterior do mesmo mês, apagados na substituição.
    public var replaced: Int
    /// Lançamentos que receberam tags/categoria/comentário de um lançamento
    /// anterior da mesma compra.
    public var suggested: Int
    /// Mantidos para clientes antigos; sempre zero desde que as parcelas
    /// futuras deixaram de ser projetadas.
    public var projectedInstallments: Int
    public var confirmedInstallments: Int
    public var failures: [ImportFailure]
    /// Lote criado, usado para desfazer a importação inteira.
    public var batchID: UUID?

    public init(
        imported: Int = 0,
        duplicates: Int = 0,
        replaced: Int = 0,
        suggested: Int = 0,
        projectedInstallments: Int = 0,
        confirmedInstallments: Int = 0,
        failures: [ImportFailure] = [],
        batchID: UUID? = nil
    ) {
        self.imported = imported
        self.duplicates = duplicates
        self.replaced = replaced
        self.suggested = suggested
        self.projectedInstallments = projectedInstallments
        self.confirmedInstallments = confirmedInstallments
        self.failures = failures
        self.batchID = batchID
    }
}

extension ImportReportDTO {
    private enum CodingKeys: String, CodingKey {
        case imported, duplicates, replaced, suggested, projectedInstallments, confirmedInstallments, failures, batchID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            imported: try container.decode(Int.self, forKey: .imported),
            duplicates: try container.decode(Int.self, forKey: .duplicates),
            replaced: try container.decodeIfPresent(Int.self, forKey: .replaced) ?? 0,
            suggested: try container.decodeIfPresent(Int.self, forKey: .suggested) ?? 0,
            projectedInstallments: try container.decodeIfPresent(Int.self, forKey: .projectedInstallments) ?? 0,
            confirmedInstallments: try container.decodeIfPresent(Int.self, forKey: .confirmedInstallments) ?? 0,
            failures: try container.decode([ImportFailure].self, forKey: .failures),
            batchID: try container.decodeIfPresent(UUID.self, forKey: .batchID)
        )
    }
}
