# CoreLedger 📊

O **CoreLedger** é uma aplicação *Full-Stack* desenvolvida inteiramente em **Swift**, criada para o gerenciamento e o registro de transações financeiras. O projeto adota uma arquitetura de **monorepo modular**, garantindo o compartilhamento rigoroso de contratos de dados entre o servidor e o app cliente, sem duplicação de código.

---

## 🌌 A constelação por trás dos nomes

"Ledger" remete ao livro-razão contábil, a fonte da verdade onde os lançamentos ficam resguardados; "Core" marca este sistema como o motor central da gestão.

A divisão interna foi inspirada no arco da constelação de Sagitário. **Kaus** vem do árabe *qaws* ("arco") e nomeia as três estrelas que o desenham — e cada módulo ocupa a posição da sua estrela:

*   **`Kaus-Australis` (ε Sgr, a ponta sul):** o **backend** em Vapor com PostgreSQL — a base estrutural que trabalha nos bastidores.
*   **`Kaus-Borealis` (λ Sgr, a ponta norte):** o **frontend** em SwiftUI — a camada visível com que a pessoa interage.
*   **`Kaus-Media` (δ Sgr, o centro):** os **contratos compartilhados (DTOs)** — a peça no meio, que liga as duas pontas sem duplicação de código.

---

## 🏗️ Arquitetura do Monorepo

O repositório está estruturado em três módulos principais:

*   **`Kaus-Media`**: Pacote Swift independente (`Swift Package`) que centraliza os contratos de dados e DTOs compartilhados (`TransactionDTO`, `AccountDTO`, `CategoryRule`), além da lógica pura de categorização, leitura de extratos CSV/OFX e planilhas `.xlsx`, parcelas, deduplicação e projeção.
*   **`Kaus-Australis`**: O backend do sistema, construído com o framework **Vapor**, utilizando o ORM *Fluent* e **PostgreSQL** para persistência robusta de dados.
*   **`Kaus-Borealis`**: O frontend nativo desenvolvido em **SwiftUI** para ecossistemas Apple (iOS / macOS), consumindo diretamente a API REST do backend.

---

## 🚀 Tecnologias Utilizadas

*   **Linguagem:** Swift 6 (o `Kaus-Media` declara `swift-tools-version: 6.0`, portanto é preciso Xcode 16 ou toolchain Swift 6.0+)
*   **Backend:** Vapor, Fluent ORM, PostgreSQL (via Docker)
*   **Frontend:** SwiftUI, Concorrência Nativa (`async/await`)
*   **Infraestrutura:** Docker Desktop, Git & GitHub

---

## ⚙️ Como Executar o Projeto Localmente

### 1. Pré-requisitos
*   Verifique se o **Docker Desktop** está rodando.
*   Tenha o **Xcode** e as ferramentas de linha de comando do Swift instalados.

### 2. Subir o Banco de Dados
```zsh
cd Kaus-Australis
docker compose up -d
```

### 3. Configurar as Variáveis de Ambiente
As credenciais do banco de dados são lidas do ambiente (o Vapor carrega o arquivo `.env` automaticamente):
```zsh
cp .env.example .env
```

| Variável | Padrão |
| --- | --- |
| `DATABASE_HOST` | `localhost` |
| `DATABASE_PORT` | `5432` |
| `DATABASE_USERNAME` | `kaus_user` |
| `DATABASE_PASSWORD` | `kaus_password` |
| `DATABASE_NAME` | `kaus_db` |
| `DATABASE_TLS` | `disable` (use `require` para bancos remotos) |
| `API_TOKEN` | vazio (em desenvolvimento as rotas ficam abertas; nos demais ambientes é obrigatório e vai no cabeçalho `Authorization: Bearer <token>`) |

> O PostgreSQL só cria o usuário e o banco na primeira inicialização do volume `pgdata`. Defina o `.env` **antes** do primeiro `docker compose up`; para alterar credenciais depois, remova o volume (`docker compose down -v`) ou altere-as diretamente no banco.

### 4. Executar o Backend (`Kaus-Australis`)
```zsh
swift run
```
As migrations são aplicadas automaticamente na inicialização. O servidor fica disponível em `http://127.0.0.1:8080`.

### 5. Executar o Frontend (`Kaus-Borealis`)
Abra `Kaus-Borealis/KausBorealis.xcodeproj` no Xcode e execute no simulador de iOS ou no macOS. O app tem sete abas — Resumo, Lançamentos, Análise, Plano, Contas, Regras e Ajustes — e consome a API em `http://127.0.0.1:8080` por padrão.

Em **Resumo** o painel de posição mostra quanto há guardado (contas do tipo caixinha/poupança e investimento), quanto está disponível (corrente e dinheiro), quanto se deve no cartão e se o líquido está positivo, empatado ou negativo; as parcelas contratadas aparecem à parte, por serem compromisso futuro e não dívida já realizada. Ainda em Resumo há gráficos de receitas/despesas por mês (incluindo os meses previstos) e a rosca de despesas por categoria do mês corrente. Em **Lançamentos** o período "Escolher" navega mês a mês, inclusive meses futuros — com um cartão filtrado, o cartão "Com previstos" mostra a fatura prevista do mês — e o botão Exportar CSV salva a lista filtrada. Os filtros aceitam conta, categoria e tag. Também dá para editar (toque na linha), selecionar vários para apagar de uma vez e desfazer uma importação inteira pela tela de importação. Em **Análise** ficam os gastos do ano, mês a mês, em barras empilhadas por categoria ou por tag (um cartão, todos os cartões ou todas as contas), com o ranking do ano; tocar num mês mostra o detalhe dele. Transferências e aportes em caixinha não contam como gasto, e as parcelas previstas aparecem mais claras. Em **Regras**, o cartão "Categorias" lista todas as categorias e tags em uso, inclusive as digitadas direto num lançamento, com as opções de renomear (renomear para um nome que já existe junta as duas) e apagar. O botão de lixeira no cabeçalho de cada categoria também apaga a categoria inteira e recategoriza os lançamentos pelas regras restantes. Em **Ajustes** é possível trocar o endereço do servidor e informar o `API_TOKEN` (deixe vazio quando o backend roda em `development`, onde o token não é exigido), além do "Apagar tudo" com escolha de escopo — só lançamentos e importações, também as contas, ou tudo inclusive as regras.

---

## 🔌 API

| Método | Rota | Corpo | Resposta |
| --- | --- | --- | --- |
| `GET` | `/api/accounts` | — | `[AccountDTO]` com saldo e contagem |
| `POST` | `/api/accounts` | `AccountDTO` | `AccountDTO` criada |
| `PUT` | `/api/accounts/:accountID` | `AccountDTO` | `AccountDTO` atualizada |
| `DELETE` | `/api/accounts/:accountID` | — | `204` |
| `GET` | `/api/category-rules` | — | `[CategoryRule]` |
| `POST` | `/api/category-rules` | `CategoryRule` | `CategoryRule` criada |
| `PUT` | `/api/category-rules/:ruleID` | `CategoryRule` | `CategoryRule` atualizada |
| `DELETE` | `/api/category-rules/:ruleID` | — | `204` |
| `POST` | `/api/category-rules/preview` | `CategoryPreviewRequest` | `CategoryPreviewResponse` (simula a regra antes de salvar) |
| `POST` | `/api/transactions/recategorize` | — | `RecategorizeResponse` (reaplica as regras a tudo) |
| `GET` | `/api/transactions` | — | `[TransactionDTO]` ordenado por data (mais recente primeiro) |
| `POST` | `/api/transactions` | `TransactionDTO` (o `id` é ignorado) | `TransactionDTO` criado |
| `PUT` | `/api/transactions/:id` | `TransactionDTO` | `TransactionDTO` atualizado |
| `PUT` | `/api/transactions/:id/transfer` | `TransferLinkRequest` (`accountID` ou `null`) | `TransactionDTO` com `transferAccountID` (cria, move ou desfaz a contrapartida) |
| `DELETE` | `/api/transactions/:id` | — | `204` |
| `DELETE` | `/api/transactions` | `BulkDeleteRequest` (`ids`) | `BulkDeleteResponse` |
| `POST` | `/api/imports` | `ImportRequestDTO` | `ImportReportDTO` (com o `batchID` do lote) |
| `GET` | `/api/imports` | — | `[ImportBatchDTO]` |
| `DELETE` | `/api/imports/:batchID` | — | `BulkDeleteResponse` (desfaz a importação) |
| `GET` | `/api/categories` | — | `[String]` com todas as categorias em uso (lançamentos, regras e contas fixas) |
| `DELETE` | `/api/categories/:category` | — | `DeleteCategoryResponse` (apaga as regras e recategoriza os lançamentos) |
| `PUT` | `/api/categories/:category` | `RenameLabelRequest` (`name`) | `LabelChangeResponse` (renomeia em lançamentos, regras e contas fixas; `409` ao juntar uma transferência com uma categoria comum) |
| `PUT` | `/api/tags/:tag` | `RenameLabelRequest` (`name`) | `LabelChangeResponse` |
| `DELETE` | `/api/tags/:tag` | — | `LabelChangeResponse` (tira a tag de tudo) |
| `GET` | `/api/analytics/spending?year=&groupBy=category\|tag&accountID=&accountKind=` | — | `SpendingReport`: gasto de cada mês por categoria ou tag e o ranking do ano |
| `POST` | `/api/reset` | `ResetRequest` (`scope` + `confirmation: "APAGAR TUDO"`) | `ResetResponse` com o que foi apagado |
| `GET` | `/api/summary` | — | `MonthlySummary` por mês, com os meses projetados |
| `GET` | `/api/position` | — | `FinancialPosition`: disponível, guardado, dívida do cartão, parcelas futuras e saldo por conta |

Contas têm tipo `checking`, `savings`, `creditCard`, `cash` ou `investment` e nome livre — cada caixinha do banco é uma conta `savings` com o nome que você quiser. Aplicações, resgates e pagamentos de fatura são reconhecidos como transferências pelas regras de seed, então guardar dinheiro não conta como despesa. As regras novas valem para importações seguintes; para reclassificar o que já está no banco, use `POST /api/transactions/recategorize` (ou o botão de recategorizar em Regras).

Transferência entre contas próprias: ao ligar uma saída da conta corrente a uma caixinha (`PUT /api/transactions/:id/transfer`), o servidor cria na caixinha a contrapartida com o valor invertido (`transferSourceID` aponta para a origem). Editar a origem atualiza a contrapartida, e apagá-la (inclusive ao desfazer a importação) apaga a contrapartida junto. Use só em contas sem extrato importado, senão o valor entra duas vezes.

`GET /api/transactions` aceita os filtros `accountID`, `from`, `to` (por dia inteiro), `search` (na descrição, categoria e comentário, ignorando maiúsculas e acentos), `category`, `tag`, `includeProjected`, `limit` (máx. 1000) e `offset`.

`TransactionDTO`:
```json
{
  "id": "1B0E1E6E-...",
  "description": "Compra Mercado",
  "amount": -150.50,
  "date": "2025-01-31T12:00:00Z",
  "category": "Alimentação",
  "accountID": "7C41...",
  "isProjected": false,
  "installment": { "number": 2, "total": 10 },
  "dedupKey": "..."
}
```
As datas trafegam em ISO-8601. `category` é opcional; quando omitida o servidor aplica as regras e, sem correspondência, grava `"Geral"`. `isProjected` marca lançamentos futuros lançados à mão (ainda fora do saldo), `note` é o comentário livre do usuário e `dedupKey` é atribuída pelo servidor (somente leitura).

### Importação

`POST /api/imports` recebe o extrato em texto (`ImportRequestDTO`: `accountID`, `content`, `filename`, `format`, `statementMonth`). O formato (CSV ou OFX) é detectado pelo conteúdo e só as linhas do arquivo são gravadas: a importação não cria parcelas futuras, apenas identifica a parcela de cada linha ("2/10"). Nas contas do tipo `creditCard`, o `statementMonth` (ex.: `"2026-12"`, sugerido pelo app a partir do nome do arquivo) identifica a fatura: reenviar a fatura do mesmo cartão e mês substitui a anterior. Cada linha nova herda categoria, tags e comentário da mesma compra já lançada (descrição compatível e mesmo total de parcelas) ou, sem parcela, as tags de um lançamento com a mesma descrição. Lançamentos já existentes são ignorados pela chave de deduplicação — o relatório devolve `imported`, `duplicates`, `replaced`, `suggested`, `failures` e o `batchID` usado para desfazer.

Para lançar algo futuro que você já conhece (ex.: IPTU em 10 vezes), use Lançamentos → + e escolha o número de parcelas: o app gera uma linha por mês, com data e valor editáveis antes de salvar.

Planilhas `.xlsx` (Excel ou Google Planilhas, em Arquivo → Fazer download → .xlsx ou .csv) são convertidas para CSV no próprio app, com `SpreadsheetReader`, antes do envio. O parser procura o cabeçalho nas primeiras linhas, ignora subtotais e avisos de rodapé e junta a coluna de parcelamento ("Parcela 2 de 12") à descrição. Nas contas de cartão, quando o pagamento da fatura vem negativo (compras positivas, como no Itaú), os sinais são invertidos; sem pagamento na fatura, decide a maioria das linhas. Quando a fatura repete a data da compra nas parcelas (uma parcela 2+ datada antes do ciclo), a parcela N passa para N-1 meses depois. Arquivos `.xls` antigos não são lidos: salve como `.xlsx` ou `.csv`.

Dá para escolher vários arquivos de uma vez: eles sobem do mais antigo para o mais recente (pela data mais recente de cada um), cada um como uma importação separada que pode ser desfeita sozinha.

---

## 🧪 Testes

```zsh
cd Kaus-Media && swift test
cd ../Kaus-Australis && swift test
```
