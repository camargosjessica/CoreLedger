import Vapor
import KausMedia

// Os DTOs são Sendable nativamente; aqui só ganham a conformidade do Vapor.
extension TransactionDTO: @retroactive Content {}
extension AccountDTO: @retroactive Content {}
extension CategoryRule: @retroactive Content {}
extension CategoryLimit: @retroactive Content {}
extension CategorySetting: @retroactive Content {}
extension ImportRequestDTO: @retroactive Content {}
extension ImportReportDTO: @retroactive Content {}
extension MonthlySummary: @retroactive Content {}
extension LedgerProjection: @retroactive Content {}
extension CategoryPreviewRequest: @retroactive Content {}
extension CategoryPreviewResponse: @retroactive Content {}
extension RecategorizeResponse: @retroactive Content {}
extension ImportBatchDTO: @retroactive Content {}
extension BulkDeleteRequest: @retroactive Content {}
extension BulkDeleteResponse: @retroactive Content {}
extension BulkUpdateResponse: @retroactive Content {}
extension BulkUpdateRequest: @retroactive Content {}
extension ResetRequest: @retroactive Content {}
extension ResetResponse: @retroactive Content {}
extension DeleteCategoryResponse: @retroactive Content {}
extension FinancialPosition: @retroactive Content {}
extension RecurringCommitment: @retroactive Content {}
extension AnnualPlan: @retroactive Content {}
extension PlanResponse: @retroactive Content {}
extension SpendingReport: @retroactive Content {}
extension RenameLabelRequest: @retroactive Content {}
extension LabelChangeResponse: @retroactive Content {}
extension TransferLinkRequest: @retroactive Content {}
