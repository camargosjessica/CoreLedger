import Foundation

/// Lançamento já gravado, com o que o usuário pode ter ajustado à mão.
public struct LabeledTransaction: Sendable, Hashable {
    public var description: String
    public var installment: Installment?
    public var category: String
    public var tags: [String]
    public var note: String?

    public init(description: String, installment: Installment?, category: String, tags: [String], note: String?) {
        self.description = description
        self.installment = installment
        self.category = category
        self.tags = tags
        self.note = note
    }
}

/// Sugere categoria, tags e comentário para uma linha importada a partir do
/// que já foi lançado: a mesma compra parcelada (descrição compatível e mesmo
/// total de parcelas) leva tudo; a mesma descrição exata leva só as tags.
public enum LabelSuggester {
    public struct Suggestion: Sendable, Equatable {
        public var category: String?
        public var tags: [String]
        public var note: String?
    }

    /// - Parameter history: do mais relevante para o menos (fatura substituída
    ///   primeiro, depois os mais recentes).
    public static func suggestion(for transaction: ImportedTransaction, in history: [LabeledTransaction]) -> Suggestion? {
        if let installment = transaction.installment {
            let sameInstallment = history.first { candidate in
                candidate.installment == installment
                    && InstallmentDescription.matches(candidate.description, transaction.description)
            }
            let samePurchase = sameInstallment ?? history.first { candidate in
                candidate.installment?.total == installment.total
                    && InstallmentDescription.matches(candidate.description, transaction.description)
            }
            guard let match = samePurchase else { return nil }
            return Suggestion(category: match.category, tags: match.tags, note: match.note)
        }

        let description = TextNormalizer.normalize(transaction.description)
        if let match = history.first(where: { $0.installment == nil && !$0.tags.isEmpty && TextNormalizer.normalize($0.description) == description }) {
            return Suggestion(category: nil, tags: match.tags, note: nil)
        }
        return nil
    }
}
