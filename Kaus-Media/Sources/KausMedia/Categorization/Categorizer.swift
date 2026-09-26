import Foundation

/// Aplica um conjunto de `CategoryRule` a uma descrição.
///
/// O categorizador não conhece nenhuma regra: ele recebe as que estiverem
/// cadastradas. Servidor e app compartilham esta implementação para que a
/// mesma descrição produza sempre a mesma categoria.
public struct Categorizer: Sendable {
    public struct Match: Sendable, Equatable {
        public let category: String
        public let rule: CategoryRule
    }

    private let compiledRules: [CompiledRule]

    public init(rules: [CategoryRule]) {
        self.compiledRules = rules
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                if lhs.term.count != rhs.term.count { return lhs.term.count > rhs.term.count }
                return lhs.term < rhs.term
            }
            .compactMap(CompiledRule.init)
    }

    /// Primeira regra que casa, na ordem de prioridade.
    public func match(description: String, amount: Double) -> Match? {
        let normalized = TextNormalizer.normalize(description)
        for compiled in compiledRules where compiled.rule.amountScope.matches(amount) {
            if compiled.matches(normalized) {
                return Match(category: compiled.rule.category, rule: compiled.rule)
            }
        }
        return nil
    }

    /// Categoria da descrição, ou o rótulo padrão de entrada/saída se nenhuma regra casar.
    public func category(for description: String, amount: Double) -> String {
        match(description: description, amount: amount)?.category
            ?? (amount >= 0 ? CategoryRule.uncategorizedCredit : CategoryRule.uncategorizedDebit)
    }

    /// Categorias marcadas como transferência — excluídas das projeções.
    public var transferCategories: Set<String> {
        Set(compiledRules.filter(\.rule.isTransfer).map(\.rule.category))
    }
}

private struct CompiledRule: Sendable {
    let rule: CategoryRule
    private let regex: NSRegularExpression?
    private let literal: String?

    init?(rule: CategoryRule) {
        let term = TextNormalizer.normalize(rule.term)
        guard !term.isEmpty else { return nil }
        self.rule = rule

        switch rule.matchKind {
        case .contains:
            self.literal = term
            self.regex = nil
        case .word:
            // Fronteiras explícitas em vez de `\b`, para funcionar também com
            // termos que começam ou terminam em caractere não alfanumérico.
            let pattern = "(?<![\\p{L}\\p{N}])"
                + NSRegularExpression.escapedPattern(for: term)
                + "(?![\\p{L}\\p{N}])"
            self.literal = nil
            self.regex = try? NSRegularExpression(pattern: pattern)
        case .regex:
            self.literal = nil
            guard let compiled = try? NSRegularExpression(pattern: term) else { return nil }
            self.regex = compiled
        }

        if literal == nil && regex == nil { return nil }
    }

    func matches(_ normalizedDescription: String) -> Bool {
        if let literal {
            return normalizedDescription.contains(literal)
        }
        guard let regex else { return false }
        let range = NSRange(normalizedDescription.startIndex..., in: normalizedDescription)
        return regex.firstMatch(in: normalizedDescription, range: range) != nil
    }
}
