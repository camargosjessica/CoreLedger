import Fluent
import Vapor
import KausMedia

/// Preferências de uma categoria; no máximo uma linha por categoria.
final class CategorySettingModel: Model, @unchecked Sendable {
    static let schema = "category_settings"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "category")
    var category: String

    @Field(key: "is_essential")
    var isEssential: Bool

    init() { }

    init(setting: CategorySetting) {
        self.category = setting.category
        self.isEssential = setting.isEssential
    }

    func toDTO() -> CategorySetting {
        CategorySetting(category: category, isEssential: isEssential)
    }
}
