import Vapor

extension LedgerError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .transactionNotFound, .accountNotFound, .importNotFound:
            return .notFound
        case .counterpartAlreadyExists, .duplicateTransaction:
            return .conflict
        case .descriptionRequired, .counterpartIsReadOnly, .transferToSameAccount,
             .transferAlreadyTargetsAccount, .tooManyItems:
            return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .transactionNotFound: return "Lançamento não encontrado"
        case .accountNotFound: return "Conta não encontrada"
        case .importNotFound: return "Importação não encontrada"
        case .descriptionRequired: return "A descrição é obrigatória"
        case .counterpartIsReadOnly:
            return "Este lançamento é a contrapartida de uma transferência: edite o original"
        case .transferToSameAccount: return "Escolha uma conta diferente da conta do lançamento"
        case .transferAlreadyTargetsAccount:
            return "A transferência já vai para essa conta: escolha outra conta ou desfaça a transferência"
        case .counterpartAlreadyExists: return "Este lançamento já tem uma contrapartida"
        case .duplicateTransaction: return "Já existe um lançamento igual nessa data e conta"
        case let .tooManyItems(limit): return "No máximo \(limit) lançamentos por vez"
        }
    }
}
