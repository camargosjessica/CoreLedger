import Vapor

extension LedgerError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .transactionNotFound, .accountNotFound, .importNotFound, .ruleNotFound, .commitmentNotFound:
            return .notFound
        case .counterpartAlreadyExists, .duplicateTransaction, .accountNameTaken, .incompatibleCategoryMerge:
            return .conflict
        default:
            return .badRequest
        }
    }

    var reason: String {
        switch self {
        case .transactionNotFound: return "Lançamento não encontrado"
        case .accountNotFound: return "Conta não encontrada"
        case .importNotFound: return "Importação não encontrada"
        case .ruleNotFound: return "Regra não encontrada"
        case .commitmentNotFound: return "Compromisso não encontrado"

        case .descriptionRequired: return "A descrição é obrigatória"
        case .counterpartIsReadOnly:
            return "Este lançamento é a contrapartida de uma transferência: edite o original"
        case .transferToSameAccount: return "Escolha uma conta diferente da conta do lançamento"
        case .transferAlreadyTargetsAccount:
            return "A transferência já vai para essa conta: escolha outra conta ou desfaça a transferência"
        case .counterpartAlreadyExists: return "Este lançamento já tem uma contrapartida"
        case .duplicateTransaction: return "Já existe um lançamento igual nessa data e conta"
        case let .tooManyItems(limit): return "No máximo \(limit) lançamentos por vez"
        case .emptyFile: return "Arquivo vazio"

        case .accountNameRequired: return "O nome da conta é obrigatório"
        case let .accountNameTaken(name): return "Já existe uma conta com o nome \(name)"

        case .ruleTermRequired: return "O termo da regra é obrigatório"
        case .ruleCategoryRequired: return "A categoria da regra é obrigatória"
        case let .regexTooLong(limit): return "Expressão regular longa demais (máximo \(limit) caracteres)"
        case let .invalidRegex(term): return "Expressão regular inválida: \(term)"
        case .invalidCategory: return "Categoria inválida"
        case .invalidTag: return "Tag inválida"
        case .newNameRequired: return "O novo nome é obrigatório"
        case let .incompatibleCategoryMerge(name, current):
            return "\(name) e \(current) não podem ser juntadas: só uma delas é transferência."

        case .nameRequired: return "O nome é obrigatório"
        case .categoryRequired: return "A categoria é obrigatória"
        case .invalidAmount: return "Valor inválido"
        case .endBeforeStart: return "O mês final é anterior ao inicial"
        case let .invalidOverrideMonth(month): return "Mês inválido em valores por mês: \(month)"
        case let .invalidOverrideAmount(month): return "Valor inválido para \(month)"
        case let .invalidPriceChangeMonth(month): return "Mês inválido em reajustes: \(month)"
        case let .invalidPriceChangeAmount(month): return "Valor inválido para o reajuste de \(month)"
        case let .invalidYearMonth(field): return "\(field) deve ser AAAA-MM com ano entre 1 e 9999"
        case .limitMustBePositive: return "O limite deve ser maior que zero"
        case .invalidYear: return "Ano inválido"

        case let .invalidResetConfirmation(expected): return "Confirmação inválida: envie \"\(expected)\""
        }
    }
}
