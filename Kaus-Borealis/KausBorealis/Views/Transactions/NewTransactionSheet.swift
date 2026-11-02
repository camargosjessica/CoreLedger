import SwiftUI
import KausMedia

/// Lançamento manual. Com mais de uma parcela (ex.: IPTU em 10 vezes), gera uma
/// linha por mês, cada uma com data e valor editáveis antes de salvar.
struct NewTransactionSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var form = NewTransactionForm()

    var body: some View {
        NavigationStack {
            Form {
                Section("Lançamento") {
                    TextField("Descrição", text: $form.description)
                    TextField(
                        form.hasInstallments ? "Valor de cada parcela (negativo para despesa)" : "Valor (negativo para despesa)",
                        text: $form.amount
                    )
                    DatePicker(form.hasInstallments ? "Primeira parcela" : "Data", selection: $form.date, displayedComponents: .date)
                    Picker("Conta", selection: $form.accountID) {
                        Text("Sem conta").tag(UUID?.none)
                        ForEach(store.accounts.all) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    Stepper("Parcelas: \(form.installmentCount)", value: $form.installmentCount, in: 1...60)
                }

                if form.hasInstallments {
                    Section {
                        ForEach($form.installments) { $draft in
                            HStack {
                                Text("\(draft.number)/\(form.installmentCount)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 44, alignment: .leading)
                                DatePicker("Data", selection: $draft.date, displayedComponents: .date)
                                    .labelsHidden()
                                TextField("Valor", text: $draft.amount)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    } header: {
                        Text("Parcelas")
                    } footer: {
                        Text(
                            "Total: \(form.installmentTotal.brl). Ajuste a data ou o valor de qualquer parcela antes de salvar. Parcelas com data futura não entram no saldo até o dia chegar."
                        )
                    }
                }

                Section("Categoria") {
                    CategoryField(category: $form.category, known: store.categories, placeholder: "Categoria (opcional)")
                }

                Section("Comentário") {
                    TextField("O que foi essa compra?", text: $form.note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Novo lançamento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(form.hasInstallments ? "Salvar \(form.installmentCount)" : "Salvar") { save() }
                        .disabled(!form.isValid)
                }
            }
        }
    }

    private func save() {
        guard let transactions = form.transactions() else { return }
        Task {
            await store.transactions.add(transactions)
            dismiss()
        }
    }
}
