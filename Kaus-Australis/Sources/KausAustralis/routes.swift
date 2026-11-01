import Vapor

func routes(_ app: Application) throws {
    let api: any RoutesBuilder
    switch (Environment.get("API_TOKEN"), app.environment) {
    case let (.some(token), _) where !token.isEmpty:
        api = app.grouped(APITokenMiddleware(token: token))
    case (_, .development), (_, .testing):
        app.logger.warning("API_TOKEN ausente: rotas expostas sem autenticação (apenas desenvolvimento)")
        api = app
    default:
        throw Abort(.internalServerError, reason: "API_TOKEN é obrigatório fora de desenvolvimento")
    }

    try api.register(collection: AccountController())
    try api.register(collection: CategoryRuleController())
    try api.register(collection: TransactionController())
    try api.register(collection: PlanController())
    try api.register(collection: MaintenanceController())
    try api.register(collection: AnalyticsController())
    try api.register(collection: LabelController())
    try api.register(collection: CategoryLimitController())
    try api.register(collection: CategorySettingController())
}
