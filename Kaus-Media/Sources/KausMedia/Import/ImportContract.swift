import Foundation

/// Corpo de `POST /api/imports`: conteúdo do extrato em texto.
public struct ImportRequestDTO: Codable, Sendable {
    public var accountID: UUID
    public var filename: String?
    public var content: String
    /// Sobrescreve a detecção automática pelo conteúdo/extensão.
    public var format: StatementFormat?
    /// Sobrescreve o comportamento padrão do tipo de conta
    /// (faturas de cartão expandem parcelas; contas correntes, não).
    public var expandInstallments: Bool?

    public init(
        accountID: UUID,
        filename: String? = nil,
        content: String,
        format: StatementFormat? = nil,
        expandInstallments: Bool? = nil
    ) {
        self.accountID = accountID
        self.filename = filename
        self.content = content
        self.format = format
        self.expandInstallments = expandInstallments
    }
}

/// Resultado de uma importação, para exibição ao usuário.
public struct ImportReportDTO: Codable, Sendable {
    public var imported: Int
    /// Já existiam com a mesma chave e foram ignorados.
    public var duplicates: Int
    /// Parcelas futuras criadas a partir das compras parceladas da fatura.
    public var projectedInstallments: Int
    /// Projeções que a fatura deste mês confirmou (viraram lançamentos reais).
    public var confirmedInstallments: Int
    public var failures: [ImportFailure]
    /// Lote criado, usado para desfazer a importação inteira.
    public var batchID: UUID?

    public init(
        imported: Int = 0,
        duplicates: Int = 0,
        projectedInstallments: Int = 0,
        confirmedInstallments: Int = 0,
        failures: [ImportFailure] = [],
        batchID: UUID? = nil
    ) {
        self.imported = imported
        self.duplicates = duplicates
        self.projectedInstallments = projectedInstallments
        self.confirmedInstallments = confirmedInstallments
        self.failures = failures
        self.batchID = batchID
    }
}
