import Foundation

/// Lançamentos em CSV no layout que o `StatementParser` lê (`;`, `dd/MM/aaaa`,
/// vírgula decimal): abre direto no Excel/Numbers e pode ser reimportado.
public enum TransactionCSV {
    public static func export(_ transactions: [TransactionDTO]) -> String {
        let header = ["Data", "Descrição", "Categoria", "Tags", "Valor", "Situação"]
        let rows = transactions.sorted { $0.date < $1.date }.map { transaction in
            [
                DateParser.format(transaction.date),
                transaction.description,
                transaction.category ?? "",
                transaction.tags.joined(separator: ", "),
                String(format: "%.2f", transaction.amount).replacingOccurrences(of: ".", with: ","),
                transaction.isProjected ? "Previsto" : "Realizado",
            ]
        }
        return ([header] + rows).map(CSVReader.line).joined(separator: "\n") + "\n"
    }
}
