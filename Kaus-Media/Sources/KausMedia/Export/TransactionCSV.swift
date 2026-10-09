import Foundation

/// Relatório de lançamentos em CSV (`;`, `dd/MM/aaaa`, vírgula decimal) para abrir
/// no Excel/Numbers. Não serve para reimportar: a importação ignora categoria,
/// tags e situação, e um previsto voltaria como realizado.
public enum TransactionCSV {
    public static func export(_ transactions: [TransactionDTO]) -> String {
        let header = ["Data", "Descrição", "Categoria", "Tags", "Valor", "Situação", "Comentário"]
        let rows = transactions.sorted { $0.date < $1.date }.map { transaction in
            [
                DateParser.format(transaction.date),
                transaction.description,
                transaction.category ?? "",
                transaction.tags.joined(separator: ", "),
                String(format: "%.2f", transaction.amount).replacingOccurrences(of: ".", with: ","),
                transaction.isProjected ? "Previsto" : "Realizado",
                transaction.note ?? "",
            ]
        }
        return ([header] + rows).map(CSVReader.line).joined(separator: "\n") + "\n"
    }
}
