import SwiftUI
import UniformTypeIdentifiers
import KausMedia

/// Importação de extrato ou fatura. O arquivo é lido localmente e enviado como
/// texto para `POST /api/imports`; quem interpreta é o mesmo parser do Kaus-Media
/// que o servidor usa. Planilhas `.xlsx` são convertidas para CSV antes do envio.
/// Vários arquivos sobem um por vez, cada um como uma importação separada.
struct ImportView: View {
    @Bindable var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var accountID: UUID?
    @State private var files: [StatementFile] = []
    @State private var content = ""
    @State private var format: StatementFormat?
    @State private var isChoosingFile = false
    @State private var results: [FileResult] = []
    @State private var loadProblems: [String] = []
    @State private var isSending = false
    @State private var progress: String?
    @State private var pendingUndo: ImportBatchDTO?
    @State private var undoSummary: String?

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

                Section("Arquivos") {
                    Button(files.isEmpty ? "Escolher arquivos CSV, OFX ou Excel…" : "Adicionar mais arquivos…") {
                        isChoosingFile = true
                    }
                    ForEach(files) { file in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                if let latestDate = file.latestDate {
                                    Text("Lançamentos até \(latestDate.numericDay)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                files.removeAll { $0.id == file.id }
                            } label: {
                                Label("Remover", systemImage: "xmark.circle.fill")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                    if files.count > 1 {
                        Text("Os arquivos sobem do mais antigo para o mais recente, cada um como uma importação separada.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if files.isEmpty {
                        Picker("Formato", selection: $format) {
                            Text("Detectar").tag(StatementFormat?.none)
                            Text("CSV").tag(StatementFormat?.some(.csv))
                            Text("OFX").tag(StatementFormat?.some(.ofx))
                        }
                        TextField("Ou cole o conteúdo aqui", text: $content, axis: .vertical)
                            .lineLimit(3...10)
                            .font(.caption.monospaced())
                    }
                }

                if !loadProblems.isEmpty {
                    Section("Arquivos não lidos") {
                        ForEach(loadProblems, id: \.self) { problem in
                            Text(problem).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                ForEach(results) { result in
                    Section(result.name) {
                        if let report = result.report {
                            reportRows(report)
                        } else {
                            Text("Não importado: \(result.error ?? "erro desconhecido")")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if let undoSummary {
                    Section { Text(undoSummary).font(.caption).foregroundStyle(.secondary) }
                }

                if !store.batches.isEmpty {
                    Section("Importações recentes") {
                        ForEach(store.batches) { batch in
                            Button {
                                pendingUndo = batch
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(batch.filename ?? "Importação")
                                    Text(subtitle(for: batch))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Importar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(files.count > 1 ? "Importar \(files.count)" : "Importar") { send() }
                        .disabled(accountID == nil || (files.isEmpty && content.isEmpty) || isSending)
                }
            }
            .fileImporter(
                isPresented: $isChoosingFile,
                allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                allowsMultipleSelection: true
            ) { result in
                load(result)
            }
            .overlay {
                if isSending {
                    ProgressView(progress ?? "Importando…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .confirmationDialog(
                "Desfazer esta importação?",
                isPresented: isConfirmingUndo,
                titleVisibility: .visible
            ) {
                Button("Desfazer", role: .destructive) { undo() }
            } message: {
                Text("Os lançamentos criados por ela serão apagados e as parcelas confirmadas voltam a ser projeções.")
            }
        }
    }

    @ViewBuilder
    private func reportRows(_ report: ImportReportDTO) -> some View {
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
        if let batchID = report.batchID {
            Button("Desfazer esta importação", role: .destructive) {
                pendingUndo = ImportBatchDTO(id: batchID, accountID: accountID ?? UUID())
            }
        }
    }

    private var isConfirmingUndo: Binding<Bool> {
        Binding(
            get: { pendingUndo != nil },
            set: { if !$0 { pendingUndo = nil } }
        )
    }

    private func subtitle(for batch: ImportBatchDTO) -> String {
        let date = batch.createdAt.map { $0.shortDay } ?? ""
        return "\(date) · \(batch.transactionCount) lançamento(s)"
    }

    private func undo() {
        guard let batch = pendingUndo, let id = batch.id else { return }
        pendingUndo = nil
        isSending = true
        Task {
            if let response = await store.undoImport(batchID: id) {
                undoSummary = "\(response.deleted) apagado(s), \(response.restored) projeção(ões) restaurada(s)."
                results = []
            }
            isSending = false
        }
    }

    private func load(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result else { return }
        loadProblems = []
        for url in urls {
            do {
                let file = try readStatement(at: url)
                files.removeAll { $0.source == file.source }
                files.append(file)
            } catch {
                loadProblems.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        files.sort { ($0.latestDate ?? .distantPast, $0.name) < ($1.latestDate ?? .distantPast, $1.name) }
    }

    private func readStatement(at url: URL) throws -> StatementFile {
        // Arquivo fora da sandbox do app: o acesso precisa ser aberto e devolvido.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw StatementFileError.unreadable }
        let isSpreadsheet = SpreadsheetReader.isXLSX(data) || url.pathExtension.lowercased() == "xls"
        let text = try isSpreadsheet ? SpreadsheetReader.csv(fromXLSX: data) : StatementParser.decode(data)
        guard let text else { throw StatementFileError.unreadable }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StatementFileError.empty }

        let format: StatementFormat? = isSpreadsheet ? .csv : nil
        let parsed = StatementParser.parse(content: text, filename: url.lastPathComponent, format: format)
        return StatementFile(
            source: url.standardizedFileURL,
            name: url.lastPathComponent,
            content: text,
            format: format,
            latestDate: parsed.transactions.map(\.date).max()
        )
    }

    private func send() {
        guard let accountID else { return }
        let queue = files.isEmpty
            ? [StatementFile(source: nil, name: "Conteúdo colado", content: content, format: format, latestDate: nil, isPasted: true)]
            : files
        isSending = true
        results = []
        undoSummary = nil
        Task {
            for (index, file) in queue.enumerated() {
                if queue.count > 1 { progress = "Importando \(index + 1) de \(queue.count)…" }
                do {
                    let report = try await store.importStatement(
                        ImportRequestDTO(
                            accountID: accountID,
                            filename: file.isPasted ? nil : file.name,
                            content: file.content,
                            format: file.format
                        )
                    )
                    results.append(FileResult(name: file.name, report: report))
                    files.removeAll { $0.id == file.id }
                } catch {
                    results.append(FileResult(name: file.name, error: LedgerStore.message(for: error)))
                }
            }
            progress = nil
            isSending = false
        }
    }
}

private struct StatementFile: Identifiable {
    let id = UUID()
    /// Identifica o arquivo escolhido; dois extratos podem ter o mesmo nome.
    var source: URL?
    var name: String
    var content: String
    var format: StatementFormat?
    /// Data mais recente do arquivo. As faturas sobem em ordem cronológica para
    /// que cada uma confirme as parcelas que a anterior deixou previstas.
    var latestDate: Date?
    var isPasted = false
}

private struct FileResult: Identifiable {
    let id = UUID()
    var name: String
    var report: ImportReportDTO?
    var error: String?
}

private enum StatementFileError: LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Não foi possível ler o arquivo."
        case .empty: return "O arquivo está vazio."
        }
    }
}
