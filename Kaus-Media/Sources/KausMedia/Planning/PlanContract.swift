import Foundation

/// Resposta de `GET /api/plan`: a grade anual mais o que o app precisa para
/// desenhar o rodapé sem recalcular nada.
public struct PlanResponse: Codable, Sendable {
    public var plan: AnnualPlan
    public var commitments: [RecurringCommitment]
    /// Todas as tags em uso, para o app sugerir enquanto o usuário digita.
    public var knownTags: [String]

    public init(plan: AnnualPlan, commitments: [RecurringCommitment], knownTags: [String]) {
        self.plan = plan
        self.commitments = commitments
        self.knownTags = knownTags
    }
}
