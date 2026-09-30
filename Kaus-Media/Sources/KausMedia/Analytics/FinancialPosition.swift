import Foundation

/// Situação de uma conta dentro da posição consolidada.
public struct AccountPosition: Codable, Sendable, Hashable, Identifiable {
    public var accountID: UUID?
    public var name: String
    public var kind: AccountKind
    /// Saldo realizado: parcelas projetadas não entram.
    public var balance: Double

    public var id: String { accountID?.uuidString ?? name }

    public init(accountID: UUID?, name: String, kind: AccountKind, balance: Double) {
        self.accountID = accountID
        self.name = name
        self.kind = kind
        self.balance = balance
    }
}

/// "Estou empatada, positiva ou negativa?" comparando o que está guardado e
/// disponível com o que ainda se deve no cartão.
public enum PositionStatus: String, Codable, Sendable {
    case positive
    case even
    case negative

    public var title: String {
        switch self {
        case .positive: return "Positiva"
        case .even: return "Empatada"
        case .negative: return "Negativa"
        }
    }
}

/// Fotografia do patrimônio: quanto está guardado em caixinhas e investimentos,
/// quanto está disponível em conta e quanto ainda se deve no cartão.
public struct FinancialPosition: Codable, Sendable, Hashable {
    /// Contas correntes e dinheiro.
    public var available: Double
    /// Poupanças (caixinhas) e investimentos.
    public var saved: Double
    /// Dívida do cartão em aberto, sempre positiva.
    public var creditCardDebt: Double
    /// Parcelas futuras já contratadas e ainda não confirmadas pela fatura,
    /// sempre positiva. Fica fora do líquido: ainda não é dívida realizada.
    public var upcomingInstallments: Double
    public var accounts: [AccountPosition]

    /// Disponível + guardado − cartão.
    public var net: Double { available + saved - creditCardDebt }

    /// Empatada quando a diferença é menor que um centavo, para que ruído de
    /// ponto flutuante não vire "negativa por R$ 0,001".
    public var status: PositionStatus {
        if net > 0.005 { return .positive }
        if net < -0.005 { return .negative }
        return .even
    }

    public init(
        available: Double = 0,
        saved: Double = 0,
        creditCardDebt: Double = 0,
        upcomingInstallments: Double = 0,
        accounts: [AccountPosition] = []
    ) {
        self.available = available
        self.saved = saved
        self.creditCardDebt = creditCardDebt
        self.upcomingInstallments = upcomingInstallments
        self.accounts = accounts
    }

    /// Consolida as contas pelo tipo. `upcomingInstallments` vem à parte porque
    /// as parcelas projetadas não compõem o saldo de nenhuma conta.
    public static func make(
        accounts: [AccountPosition],
        upcomingInstallments: Double = 0
    ) -> FinancialPosition {
        var available: Double = 0
        var saved: Double = 0
        var debt: Double = 0

        for account in accounts {
            switch account.kind {
            case .checking, .cash:
                available += account.balance
            case .savings, .investment:
                saved += account.balance
            case .creditCard:
                // O extrato do cartão traz as compras como negativas; a dívida
                // é o oposto disso. Saldo positivo (crédito a favor) não vira
                // dívida negativa: reduz o que se deve.
                debt -= account.balance
            }
        }

        return FinancialPosition(
            available: available,
            saved: saved,
            creditCardDebt: debt,
            upcomingInstallments: abs(upcomingInstallments),
            accounts: accounts.sorted { $0.name < $1.name }
        )
    }
}
