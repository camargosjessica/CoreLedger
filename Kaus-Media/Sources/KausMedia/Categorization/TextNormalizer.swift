import Foundation

/// Normalização compartilhada por categorização e deduplicação.
///
/// O locale é fixo (`en_US_POSIX`) de propósito: o mesmo texto precisa produzir
/// exatamente o mesmo resultado no servidor Linux e no app, independentemente da
/// configuração do dispositivo.
public enum TextNormalizer {
    private static let fixedLocale = Locale(identifier: "en_US_POSIX")

    /// Minúsculas, sem acentos e com espaços em branco colapsados.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: fixedLocale
        )
        return folded
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
