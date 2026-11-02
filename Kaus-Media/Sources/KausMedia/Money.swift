import Foundation

/// Valor monetário em reais, guardado como um número inteiro de centavos.
///
/// `Double` não representa 0,10 com exatidão: somas de centenas de lançamentos
/// acumulam erro e duas parcelas "iguais" deixam de ser iguais. Em centavos a
/// aritmética é exata e a comparação é direta.
///
/// No JSON o valor continua sendo um número decimal (`-150.5`), para manter o
/// contrato da API; a conversão para centavos acontece na borda.
public struct Money: Hashable, Comparable, Sendable {
    public var cents: Int

    public init(cents: Int) {
        self.cents = cents
    }

    /// Converte um valor decimal arredondando para o centavo mais próximo
    /// (metade se afasta do zero).
    ///
    /// Passa pela representação decimal mais curta do `Double` (`1.005`, e não
    /// `1.00499999…`), para arredondar o número que a pessoa de fato escreveu.
    public init(_ value: Double) {
        if value.isFinite, let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) {
            self.init(decimal)
        } else {
            self.init(cents: 0)
        }
    }

    /// Converte um `Decimal` arredondando para o centavo mais próximo.
    public init(_ value: Decimal) {
        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        self.cents = NSDecimalNumber(decimal: rounded).intValue
    }

    /// Lê um decimal com ponto como separador (`"-1234.56"`), sem passar por
    /// ponto flutuante.
    public init?(decimalString: String) {
        guard let decimal = Decimal(string: decimalString, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self.init(decimal)
    }

    public static let zero = Money(cents: 0)

    /// Valor em reais como `Decimal`, exato.
    public var decimalValue: Decimal {
        Decimal(cents) / 100
    }

    /// Valor em reais como `Double`, para gráficos e proporções. Não use em somas.
    public var doubleValue: Double {
        Double(cents) / 100
    }

    public var isNegative: Bool { cents < 0 }
    public var isPositive: Bool { cents > 0 }
    public var isZero: Bool { cents == 0 }

    /// Valor absoluto.
    public var magnitude: Money { Money(cents: Swift.abs(cents)) }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.cents < rhs.cents
    }
}

// MARK: - Aritmética

extension Money: AdditiveArithmetic {
    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents + rhs.cents)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents - rhs.cents)
    }

    public static prefix func - (value: Money) -> Money {
        Money(cents: -value.cents)
    }

    public static func * (lhs: Money, rhs: Int) -> Money {
        Money(cents: lhs.cents * rhs)
    }

    public static func * (lhs: Int, rhs: Money) -> Money {
        rhs * lhs
    }

    /// Divide em partes iguais (ex.: média mensal), arredondando para o centavo
    /// mais próximo. Dividir por zero dá zero.
    public static func / (lhs: Money, rhs: Int) -> Money {
        guard rhs != 0 else { return .zero }
        return Money(Decimal(lhs.cents) / Decimal(rhs) / 100)
    }

    /// Proporção entre dois valores (ex.: gasto / limite). Zero quando o divisor é zero.
    public static func / (lhs: Money, rhs: Money) -> Double {
        rhs.cents == 0 ? 0 : Double(lhs.cents) / Double(rhs.cents)
    }
}

/// Valor absoluto, no mesmo espírito de `Swift.abs` (que exige `SignedNumeric`,
/// e multiplicar dinheiro por dinheiro não faz sentido).
public func abs(_ value: Money) -> Money {
    value.magnitude
}

extension Sequence where Element == Money {
    /// Soma exata.
    public func sum() -> Money {
        reduce(.zero, +)
    }
}

// MARK: - Literais

/// `0` e `-150.5` em testes e valores padrão. Literais decimais passam por
/// `Double`, mas são arredondados para o centavo na hora.
extension Money: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public init(integerLiteral value: Int) {
        self.cents = value * 100
    }

    public init(floatLiteral value: Double) {
        self.init(value)
    }
}

// MARK: - Codable

extension Money: Codable {
    /// Aceita o número decimal do contrato da API (`-150.5`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            self.init(decimal)
        } else {
            self.init(try container.decode(Double.self))
        }
    }

    /// Emite o número decimal do contrato da API. `Decimal` evita que 0,1 vire
    /// `0.10000000000000001` no JSON.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(decimalValue)
    }
}

// MARK: - Texto

extension Money: CustomStringConvertible {
    /// `"-150.50"`: ponto como separador e sempre duas casas, independente do locale.
    public var description: String {
        let sign = cents < 0 ? "-" : ""
        let absolute = Swift.abs(cents)
        return "\(sign)\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }
}
