import Fluent
import Vapor
import KausMedia

/// Uma execução de importação. Guarda o suficiente para desfazê-la: os
/// lançamentos criados apontam para o lote, e as projeções que a importação
/// confirmou têm o estado anterior registrado em `confirmations`.
final class ImportBatchModel: Model, @unchecked Sendable {
    static let schema = "import_batches"

    /// Estado de uma projeção antes de ser confirmada pela fatura, mais o estado
    /// deixado pela confirmação: desfazer só reverte o que ainda está como a
    /// importação deixou, para não apagar correções manuais posteriores.
    struct ConfirmationSnapshot: Codable, Sendable {
        var transactionID: UUID
        var date: Date
        var amount: Double
        var externalID: String?
        /// Lote que havia criado a projeção; ao desfazer, ela volta a pertencer a ele.
        var previousBatchID: UUID?
        var confirmedDate: Date?
        var confirmedAmount: Double?
    }

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "account_id")
    var account: AccountModel

    @OptionalField(key: "filename")
    var filename: String?

    /// Envelope em objeto: um array Swift seria gravado como `jsonb[]`, e a coluna é `jsonb`.
    struct ConfirmationLog: Codable, Sendable {
        var snapshots: [ConfirmationSnapshot]
    }

    @Field(key: "confirmations")
    var confirmationLog: ConfirmationLog

    var confirmations: [ConfirmationSnapshot] {
        get { confirmationLog.snapshots }
        set { confirmationLog = ConfirmationLog(snapshots: newValue) }
    }

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() { }

    init(id: UUID? = nil, accountID: UUID, filename: String?, confirmations: [ConfirmationSnapshot] = []) {
        self.id = id
        self.$account.id = accountID
        self.filename = filename
        self.confirmationLog = ConfirmationLog(snapshots: confirmations)
    }
}

extension ImportBatchModel {
    func toDTO(transactionCount: Int) -> ImportBatchDTO {
        ImportBatchDTO(
            id: id,
            accountID: $account.id,
            filename: filename,
            createdAt: createdAt,
            transactionCount: transactionCount,
            confirmedCount: confirmations.count
        )
    }
}
