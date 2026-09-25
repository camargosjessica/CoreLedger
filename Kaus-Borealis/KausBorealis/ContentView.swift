import SwiftUI
import KausMedia

struct ContentView: View {
    @State private var transactions: [TransactionDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Buscando transações...")
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Erro ao conectar",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if transactions.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma transação",
                        systemImage: "tray",
                        description: Text("Seu ledger está limpo por enquanto.")
                    )
                } else {
                    List(transactions, id: \.id) { transaction in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(transaction.description)
                                    .font(.headline)
                                Text(transaction.category ?? "Geral")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "R$ %.2f", transaction.amount))
                                    .font(.headline)
                                    .bold()
                                Text(transaction.date, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("CoreLedger")
            .toolbar {
                Button {
                    Task { await loadTransactions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .task {
                await loadTransactions()
            }
        }
    }

    // Função assíncrona que consome a API do Vapor
    func loadTransactions() async {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "http://127.0.0.1:8080/api/transactions") else {
            errorMessage = "URL inválida"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([TransactionDTO].self, from: data)
            self.transactions = decoded
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    ContentView()
}
