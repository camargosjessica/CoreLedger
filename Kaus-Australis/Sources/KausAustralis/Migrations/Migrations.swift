import Fluent

/// Ordem de aplicação das migrations. Novas entram sempre no fim: a ordem é
/// parte do histórico do banco.
enum Migrations {
    static var all: [any Migration] {
        [
            CreateTransactionMigration(),
            CreateAccountMigration(),
            CreateCategoryRuleMigration(),
            CreateImportBatchMigration(),
            AddTransactionImportFieldsMigration(),
            AddTagsMigration(),
            SeedCategoryRulesMigration(),
            SeedSavingsRulesMigration(),
            CreateRecurringCommitmentMigration(),
            AddTransferSourceMigration(),
            AddNoteAndStatementMonthMigration(),
            CreateCategoryLimitMigration(),
            CreateCategorySettingMigration(),
            ConvertTagsToSubcategoriesMigration(),
            AddCommitmentPriceChangesMigration(),
            ConvertAmountsToCentsMigration(),
            AddTransactionIndexesMigration(),
        ]
    }
}
