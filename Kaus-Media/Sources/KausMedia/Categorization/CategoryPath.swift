import Foundation

/// Categoria com subcategoria opcional, gravada como um só texto:
/// "Moradia › Energia". Assim todo o resto (regras, filtros, grade, análise)
/// continua tratando categoria como uma string.
public enum CategoryPath {
    public static let separator = " › "

    public static func parent(of category: String) -> String {
        guard let range = category.range(of: separator) else { return category }
        return String(category[..<range.lowerBound])
    }

    public static func child(of category: String) -> String? {
        guard let range = category.range(of: separator) else { return nil }
        let child = String(category[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return child.isEmpty ? nil : child
    }

    public static func join(_ parent: String, _ child: String?) -> String {
        let parent = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let child = child?.trimmingCharacters(in: .whitespacesAndNewlines), !child.isEmpty else { return parent }
        return parent + separator + child
    }

    /// `true` para a própria categoria e para as suas subcategorias.
    public static func isWithin(_ category: String, _ parent: String) -> Bool {
        category == parent || category.hasPrefix(parent + separator)
    }

    /// Categoria essencial quando ela ou a categoria-mãe está marcada.
    public static func isEssential(_ category: String, in essentials: Set<String>) -> Bool {
        essentials.contains(category) || essentials.contains(parent(of: category))
    }
}
