import Fluent

/// Tabela das linhas da grade anual: contas fixas, receitas e aportes.
struct CreateRecurringCommitmentMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("recurring_commitments")
            .id()
            .field("name", .string, .required)
            .field("category", .string, .required)
            .field("kind", .string, .required)
            .field("amount", .double, .required)
            .field("day_of_month", .int, .required)
            .field("start_month", .string, .required)
            .field("end_month", .string)
            .field("tags", .array(of: .string), .required)
            .field("is_enabled", .bool, .required, .sql(.default(true)))
            .field("overrides", .dictionary(of: .double), .required)
            .field("account_id", .uuid, .references("accounts", "id", onDelete: .setNull))
            .field("notes", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("recurring_commitments").delete()
    }
}

/// Tags em lançamentos e regras.
///
/// Entram vazias nos registros existentes: preencher o histórico aqui
/// sobrescreveria classificações feitas à mão. Use "Recategorizar" na aba
/// Regras quando quiser aplicar as sugestões ao que já está no banco.
struct AddTagsMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("transactions")
            .field("tags", .array(of: .string), .required, .sql(.default("{}")))
            .update()
        try await database.schema("category_rules")
            .field("tags", .array(of: .string), .required, .sql(.default("{}")))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("transactions").deleteField("tags").update()
        try await database.schema("category_rules").deleteField("tags").update()
    }
}
