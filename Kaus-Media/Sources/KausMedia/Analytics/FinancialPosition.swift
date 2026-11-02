import Foundation

/// Situação de uma conta dentro da posição consolidada.
public struct AccountPosition: Codable, Sendable, Hashable, Identifiable {
    public var accountID: UUID?
    public var name: String
    public var kind: AccountKind
    /// Saldo realizado: parcelas projetadas não entram.
    public var balance: Money

    public var id: String { accountID?.uuidString ?? name }

    public init(accountID: UUID?, name: String, kind: AccountKind, balance: Money) {
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
}

/// Fotografia do patrimônio: quanto está guardado em caixinhas e investimentos,
/// quanto está disponível em conta e quanto ainda se deve no cartão.
public struct FinancialPosition: Codable, Sendable, Hashable {
    /// Contas correntes e dinheiro.
    public var available: Money
    /// Poupanças (caixinhas) e investimentos.
    public var saved: Money
    /// Dívida do cartão em aberto, sempre positiva.
    public var creditCardDebt: Money
    /// Parcelas futuras já contratadas e ainda não confirmadas pela fatura,
    /// sempre positiva. Fica fora do líquido: ainda não é dívida realizada.
    public var upcomingInstallments: Money
    public var accounts: [AccountPosition]

    /// Disponível + guardado − cartão.
    public var net: Money { available + saved - creditCardDebt }

    /// Empatada quando a diferença é menor que um centavo, para que ruído de
    /// ponto flutuante não vire "negativa por R$ 0,001".
    public var status: PositionStatus {
        if net > 0.005 { return .positive }
        if net < -0.005 { return .negative }
        return .even
    }

    public init(
        available: Money = 0,
        saved: Money = 0,
        creditCardDebt: Money = 0,
        upcomingInstallments: Money = 0,
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
        upcomingInstallments: Money = 0
    ) -> FinancialPosition {
        var available: Money = 0
        var saved: Money = 0
        var debt: Money = 0

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
            upcomingInstallments: upcomingInstallments.magnitude,
            accounts: accounts.sorted { $0.name < $1.name }
        )
    }
}
