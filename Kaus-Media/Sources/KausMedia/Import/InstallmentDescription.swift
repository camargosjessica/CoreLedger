import Foundation

/// O banco corta a descrição da compra em larguras diferentes a cada fatura
/// ("shopee*shps tecnol", "shopee*shps tecnolsao paulo bra",
/// "shopee*shps tecnologia sao paulo bra"). Duas descrições são da mesma compra
/// quando começam igual, ignorando espaços e pontuação.
public enum InstallmentDescription {
    /// Começo comum exigido; descrições mais curtas precisam bater inteiras.
    static let sharedPrefix = 12
    static let minimumLength = 4

    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = compact(lhs)
        let right = compact(rhs)
        let shorter = min(left.count, right.count)
        guard shorter >= minimumLength else { return left == right }
        let common = zip(left, right).prefix { $0 == $1 }.count
        return common >= min(sharedPrefix, shorter)
    }

    private static func compact(_ text: String) -> [Character] {
        TextNormalizer.normalize(text).filter { $0.isLetter || $0.isNumber }.map { $0 }
    }
}
