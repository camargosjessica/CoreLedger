import Foundation

/// Preferências de uma categoria (ou subcategoria) que não cabem no nome.
public struct CategorySetting: Codable, Sendable, Hashable, Identifiable {
    public var category: String
    /// Conta como gasto essencial na grade do Plano, junto das subcategorias.
    public var isEssential: Bool

    public var id: String { category }

    public init(category: String, isEssential: Bool) {
        self.category = category
        self.isEssential = isEssential
    }
}
