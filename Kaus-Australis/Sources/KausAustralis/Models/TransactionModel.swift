import Fluent
import Vapor
import KausMedia

final class TransactionModel: Model, @unchecked Sendable {
    static let schema = "transactions"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "description")
    var description: String
    
    @Field(key: "amount")
    var amount: Double
    
    @Field(key: "category")
    var category: String
    
    @Field(key: "date")
    var date: Date

    @OptionalParent(key: "account_id")
    var account: AccountModel?

    /// Índice único no banco: a garantia contra reimportação do mesmo extrato.
    @OptionalField(key: "dedup_key")
    var dedupKey: String?

    /// Parcela futura já contratada, ainda não confirmada pela fatura.
    @Field(key: "is_projected")
    var isProjected: Bool

    @OptionalField(key: "installment_number")
    var installmentNumber: Int?

    @OptionalField(key: "installment_total")
    var installmentTotal: Int?

    /// `FITID` do OFX, quando o extrato de origem o fornece.
    @OptionalField(key: "external_id")
    var externalID: String?

    /// Importação que criou o lançamento, para permitir desfazê-la.
    @OptionalParent(key: "import_batch_id")
    var importBatch: ImportBatchModel?

    /// Marcadores livres, preenchidos pela regra e editáveis pelo usuário.
    @Field(key: "tags")
    var tags: [String]

    /// Comentário livre do usuário sobre o lançamento.
    @OptionalField(key: "note")
    var note: String?

    /// Preenchido só na contrapartida de uma transferência: aponta para o
    /// lançamento que a originou e que manda no valor, na data e na categoria.
    @OptionalParent(key: "transfer_source_id")
    var transferSource: TransactionModel?

    init() { }
    
    init(
        id: UUID? = nil,
        description: String,
        amount: Double,
        category: String,
        date: Date,
        accountID: UUID? = nil,
        dedupKey: String? = nil,
        isProjected: Bool = false,
        installment: Installment? = nil,
        externalID: String? = nil,
        tags: [String] = [],
        note: String? = nil
    ) {
        self.id = id
        self.description = description
        self.amount = amount
        self.category = category
        self.date = date
        self.$account.id = accountID
        self.dedupKey = dedupKey
        self.isProjected = isProjected
        self.installmentNumber = installment?.number
        self.installmentTotal = installment?.total
        self.externalID = externalID
        self.tags = TagSet.normalize(tags)
        self.note = TransactionNote.normalize(note)
    }
}

extension TransactionModel {
    var installment: Installment? {
        guard let installmentNumber, let installmentTotal else { return nil }
        return Installment(number: installmentNumber, total: installmentTotal)
    }

    /// Torna este lançamento o espelho de `origin` na própria conta: o mesmo
    /// dinheiro, com o sinal invertido. Sem chave de dedup, para não colidir
    /// com a importação de outro extrato.
    func mirror(_ origin: TransactionModel) {
        description = origin.description
        amount = -origin.amount
        category = origin.category
        date = origin.date
        isProjected = origin.isProjected
        tags = origin.tags
        note = origin.note
        dedupKey = nil
        installmentNumber = nil
        installmentTotal = nil
        externalID = nil
        $transferSource.id = origin.id
    }

    /// Re-espelha a contrapartida, se houver, depois de este lançamento mudar.
    func syncCounterpart(on db: any Database) async throws {
        guard let id else { return }
        guard let counterpart = try await TransactionModel.query(on: db)
            .filter(\.$transferSource.$id == id)
            .first()
        else { return }
        counterpart.mirror(self)
        try await counterpart.update(on: db)
    }
}
