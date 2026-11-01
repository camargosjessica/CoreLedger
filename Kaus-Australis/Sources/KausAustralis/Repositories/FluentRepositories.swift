import Fluent
import FluentSQL
import Foundation
import KausMedia
import Vapor

struct FluentTransactionRepository: TransactionRepository {
    let database: any Database

    func list(_ filter: TransactionFilter) async throws -> [TransactionModel] {
        var builder = TransactionModel.query(on: database).sort(\.$date, .descending)
        if let accountID = filter.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        }
        if let from = filter.from {
            builder = builder.filter(\.$date >= LedgerCalendar.startOfDay(from))
        }
        if let to = filter.to {
            // O filtro é por dia: `to` na meia-noite ainda inclui o dia inteiro.
            builder = builder.filter(\.$date < LedgerCalendar.addingDays(1, to: LedgerCalendar.startOfDay(to)))
        }
        if !filter.includeProjected {
            builder = builder.filter(\.$isProjected == false)
        }
        if let category = filter.category {
            let subcategories = category + CategoryPath.separator
            builder = builder.group(.or) { group in
                group.filter(\.$category == category)
                    .filter(\.$category =~ subcategories)
            }
        }
        if let tag = filter.tag.flatMap({ TagSet.normalize([$0]).first }) {
            builder = builder.filter(.sql(embed: "\(ident: "tags") @> ARRAY[\(bind: tag)]::text[]"))
        }
        if let search = filter.search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            let pattern = TextSearch.pattern(for: search)
            builder = builder.group(.or) { group in
                for column in ["description", "category", "note"] {
                    group.filter(TextSearch.matches(column: column, pattern: pattern))
                }
            }
        }
        return try await builder
            .range(lower: filter.offset, upper: filter.offset + filter.limit - 1)
            .all()
    }

    func find(_ id: UUID) async throws -> TransactionModel? {
        try await TransactionModel.find(id, on: database)
    }

    func find(ids: [UUID], includingCounterparts: Bool) async throws -> [TransactionModel] {
        guard !ids.isEmpty else { return [] }
        var builder = TransactionModel.query(on: database).filter(\.$id ~~ ids)
        if !includingCounterparts {
            builder = builder.filter(\.$transferSource.$id == nil)
        }
        return try await builder.all()
    }

    func find(dedupKey: String) async throws -> TransactionModel? {
        try await TransactionModel.query(on: database).filter(\.$dedupKey == dedupKey).first()
    }

    func counterpart(of sourceID: UUID) async throws -> TransactionModel? {
        try await TransactionModel.query(on: database)
            .filter(\.$transferSource.$id == sourceID)
            .first()
    }

    func counterparts(of sourceIDs: [UUID]) async throws -> [TransactionModel] {
        guard !sourceIDs.isEmpty else { return [] }
        return try await TransactionModel.query(on: database)
            .filter(\.$transferSource.$id ~~ sourceIDs.map { Optional($0) })
            .all()
    }

    func inBatch(_ batchID: UUID) async throws -> [TransactionModel] {
        try await TransactionModel.query(on: database)
            .filter(\.$importBatch.$id == batchID)
            .all()
    }

    func create(_ model: TransactionModel) async throws {
        try await mappingConstraintFailure { try await model.create(on: database) }
    }

    func update(_ model: TransactionModel) async throws {
        try await mappingConstraintFailure { try await model.update(on: database) }
    }

    func delete(_ model: TransactionModel) async throws {
        try await model.delete(on: database)
    }

    /// O índice único de `dedup_key` é a garantia contra duplicatas; aqui a
    /// violação vira um erro de domínio.
    private func mappingConstraintFailure(_ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch let error as any DatabaseError where error.isConstraintFailure {
            throw LedgerError.duplicateTransaction
        }
    }
}

struct FluentAccountRepository: AccountRepository {
    let database: any Database

    func exists(_ id: UUID) async throws -> Bool {
        try await AccountModel.find(id, on: database) != nil
    }
}

struct FluentImportBatchRepository: ImportBatchRepository {
    let database: any Database

    func find(_ id: UUID) async throws -> ImportBatchModel? {
        try await ImportBatchModel.find(id, on: database)
    }

    func delete(_ batch: ImportBatchModel) async throws {
        try await batch.delete(on: database)
    }
}

extension CategoryRuleService: CategorizerSource {}

struct FluentUnitOfWork: UnitOfWork {
    let database: any Database

    var transactions: any TransactionRepository { FluentTransactionRepository(database: database) }
    var accounts: any AccountRepository { FluentAccountRepository(database: database) }
    var importBatches: any ImportBatchRepository { FluentImportBatchRepository(database: database) }
    var categorizer: any CategorizerSource { CategoryRuleService(database: database) }

    func transaction<T: Sendable>(_ work: @escaping @Sendable (any UnitOfWork) async throws -> T) async throws -> T {
        try await database.transaction { db in
            try await work(FluentUnitOfWork(database: db))
        }
    }
}

extension Request {
    var unitOfWork: any UnitOfWork { FluentUnitOfWork(database: db) }
}

/// Busca que ignora maiúsculas e acentos ("farmacia" acha "FARMÁCIA").
enum TextSearch {
    private static let accented = "áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ"
    private static let plain = "aaaaaeeeeiiiiooooouuuucnaaaaaeeeeiiiiooooouuuucn"

    /// Padrão `LIKE` já sem acentos, em minúsculas e com curingas escapados.
    static func pattern(for search: String) -> String {
        let folded = search
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(folded)%"
    }

    static func matches(column: String, pattern: String) -> DatabaseQuery.Filter {
        .sql(embed: "lower(translate(\(ident: column), \(bind: accented), \(bind: plain))) LIKE \(bind: pattern)")
    }
}
