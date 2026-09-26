import SwiftUI
import UniformTypeIdentifiers
import KausMedia

/// Importação de extrato ou fatura. O arquivo é lido localmente e enviado como
/// texto para `POST /api/imports`; quem interpreta é o mesmo parser do Kaus-Media
/// que o servidor usa.
struct ImportView: View {
    @Bindable var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var accountID: UUID?
    @State private var filename: String?
    @State private var content = ""
    @State private var format: StatementFormat?
    @State private var isChoosingFile = false
    @State private var report: ImportReportDTO?
    @State private var isSending = false

    private var selectedAccount: AccountDTO? {
        store.accounts.first { $0.id == accountID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Conta") {
                    Picker("Conta", selection: $accountID) {
                        Text("Escolha").tag(UUID?.none)
                        ForEach(store.accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    if selectedAccount?.kind == .creditCard {
                        Text("Fatura de cartão: as parcelas futuras entram como projeção.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Arquivo") {
                    Button("Escolher arquivo CSV/OFX…") { isChoosingFile = true }
                    if let filename {
                        Text(filename).font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Formato", selection: $format) {
                        Text("Detectar").tag(StatementFormat?.none)
                        Text("CSV").tag(StatementFormat?.some(.csv))
                        Text("OFX").tag(StatementFormat?.some(.ofx))
                    }
                    TextField("Ou cole o conteúdo aqui", text: $content, axis: .vertical)
                        .lineLimit(3...10)
                        .font(.caption.monospaced())
                }

                if let report {
                    Section("Resultado") {
                        LabeledContent("Importados", value: "\(report.imported)")
                        LabeledContent("Duplicados ignorados", value: "\(report.duplicates)")
                        LabeledContent("Parcelas projetadas", value: "\(report.projectedInstallments)")
                        LabeledContent("Parcelas confirmadas", value: "\(report.confirmedInstallments)")
                        ForEach(report.failures, id: \.line) { failure in
                            VStack(alignment: .leading) {
                                Text("Linha \(failure.line): \(failure.reason)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Text(failure.content)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") { send() }
                        .disabled(accountID == nil || content.isEmpty || isSending)
                }
            }
            .fileImporter(
                isPresented: $isChoosingFile,
                allowedContentTypes: [.commaSeparatedText, .plainText, .data]
            ) { result in
                load(result)
            }
            .overlay { if isSending { ProgressView() } }
        }
    }

    private func load(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result else { return }
        // Arquivo fora da sandbox do app: o acesso precisa ser aberto e devolvido.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url), let text = StatementParser.decode(data) else {
            store.errorMessage = "Não foi possível ler o arquivo."
            return
        }
        filename = url.lastPathComponent
        content = text
    }

    private func send() {
        guard let accountID else { return }
        isSending = true
        Task {
            report = await store.importStatement(
                ImportRequestDTO(
                    accountID: accountID,
                    filename: filename,
                    content: content,
                    format: format
                )
            )
            isSending = false
        }
    }
}
