import Fluent
import Vapor
import KausMedia

/// Renomear categorias e tags, e apagar tags, em todos os lugares onde aparecem:
/// lançamentos, regras e compromissos.
struct LabelController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.put("api", "categories", ":category", use: renameCategory)
        routes.put("api", "tags", ":tag", use: renameTag)
        routes.delete("api", "tags", ":tag", use: deleteTag)
    }

    /// Renomear para uma categoria que já existe junta as duas.
    func renameCategory(req: Request) async throws -> LabelChangeResponse {
        guard let current = req.parameters.get("category"), !current.isEmpty else {
            throw Abort(.badRequest, reason: "Categoria inválida")
        }
        let name = try newName(req)

        return try await req.db.transaction { db in
            var response = LabelChangeResponse()
            for model in try await TransactionModel.query(on: db).filter(\.$category == current).all() {
                model.category = name
                try await model.update(on: db)
                response.transactions += 1
            }
            for model in try await CategoryRuleModel.query(on: db).filter(\.$category == current).all() {
                model.category = name
                try await model.update(on: db)
                response.rules += 1
            }
            for model in try await RecurringCommitmentModel.query(on: db).filter(\.$category == current).all() {
                model.category = name
                try await model.update(on: db)
                response.commitments += 1
            }
            return response
        }
    }

    func renameTag(req: Request) async throws -> LabelChangeResponse {
        try await replaceTag(req, with: try newName(req))
    }

    func deleteTag(req: Request) async throws -> LabelChangeResponse {
        try await replaceTag(req, with: nil)
    }

    private func replaceTag(_ req: Request, with replacement: String?) async throws -> LabelChangeResponse {
        guard let tag = req.parameters.get("tag"), !tag.isEmpty else {
            throw Abort(.badRequest, reason: "Tag inválida")
        }

        return try await req.db.transaction { db in
            var response = LabelChangeResponse()
            for model in try await TransactionModel.query(on: db).all() {
                guard let tags = TagSet.replacing(tag, with: replacement, in: model.tags) else { continue }
                model.tags = tags
                try await model.update(on: db)
                response.transactions += 1
            }
            for model in try await CategoryRuleModel.query(on: db).all() {
                guard let tags = TagSet.replacing(tag, with: replacement, in: model.tags) else { continue }
                model.tags = tags
                try await model.update(on: db)
                response.rules += 1
            }
            for model in try await RecurringCommitmentModel.query(on: db).all() {
                guard let tags = TagSet.replacing(tag, with: replacement, in: model.tags) else { continue }
                model.tags = tags
                try await model.update(on: db)
                response.commitments += 1
            }
            return response
        }
    }

    private func newName(_ req: Request) throws -> String {
        let name = try req.content.decode(RenameLabelRequest.self).name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw Abort(.badRequest, reason: "O novo nome é obrigatório")
        }
        return name
    }
}
