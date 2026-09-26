# CoreLedger 📊

O **CoreLedger** é uma aplicação *Full-Stack* desenvolvida inteiramente em **Swift**, concebida para a gestão e registo de transações financeiras. O projeto adota uma arquitetura de **monorepo modular**, garantindo a partilha rigorosa de contratos de dados entre o servidor e a aplicação cliente, sem duplicação de código.

---

## 🌌 A constelação por trás dos nomes

"Ledger" remete ao livro-razão contábil, a fonte da verdade onde os lançamentos ficam resguardados; "Core" marca este sistema como o motor central da gestão.

A divisão interna foi inspirada no arco da constelação de Sagitário. **Kaus** vem do árabe *qaws* ("arco") e nomeia as três estrelas que o desenham — e cada módulo ocupa a posição da sua estrela:

*   **`Kaus-Australis` (ε Sgr, a ponta sul):** o **backend** em Vapor com PostgreSQL — a base estrutural que trabalha nos bastidores.
*   **`Kaus-Borealis` (λ Sgr, a ponta norte):** o **frontend** em SwiftUI — a camada visível com que a pessoa interage.
*   **`Kaus-Media` (δ Sgr, o centro):** os **contratos partilhados (DTOs)** — a peça no meio, que liga as duas pontas sem duplicação de código.

---

## 🏗️ Arquitetura do Monorepo

O repositório está estruturado em três módulos principais:

*   **`Kaus-Media`**: Pacote Swift independente (`Swift Package`) que centraliza os contratos de dados e DTOs partilhados (`TransactionDTO`, `AccountDTO`, `CategoryRule`), além da lógica pura de categorização, leitura de extratos CSV/OFX, parcelas, deduplicação e projeção.
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
*   Certifique-se de que tem o **Docker Desktop** a correr.
*   Tenha o **Xcode** e a ferramenta de linha de comandos do Swift instaladas.

### 2. Subir a Base de Dados
```zsh
cd Kaus-Australis
docker compose up -d
```

### 3. Configurar as Variáveis de Ambiente
As credenciais da base de dados são lidas do ambiente (o Vapor carrega o ficheiro `.env` automaticamente):
```zsh
cp .env.example .env
```

| Variável | Predefinição |
| --- | --- |
| `DATABASE_HOST` | `localhost` |
| `DATABASE_PORT` | `5432` |
| `DATABASE_USERNAME` | `kaus_user` |
| `DATABASE_PASSWORD` | `kaus_password` |
| `DATABASE_NAME` | `kaus_db` |
| `DATABASE_TLS` | `disable` (use `require` para bases remotas) |
| `API_TOKEN` | vazio (em desenvolvimento as rotas ficam abertas; nos demais ambientes é obrigatório e vai no cabeçalho `Authorization: Bearer <token>`) |

> O PostgreSQL só cria o utilizador e a base na primeira inicialização do volume `pgdata`. Defina o `.env` **antes** do primeiro `docker compose up`; para alterar credenciais depois, remova o volume (`docker compose down -v`) ou altere-as diretamente na base.

### 4. Executar o Backend (`Kaus-Australis`)
```zsh
swift run
```
As migrations são aplicadas automaticamente no arranque. O servidor fica disponível em `http://127.0.0.1:8080`.

### 5. Executar o Frontend (`Kaus-Borealis`)
Abra `Kaus-Borealis/KausBorealis.xcodeproj` no Xcode e execute no simulador de iOS ou no macOS. O app tem cinco abas — Resumo, Lançamentos, Contas, Regras e Ajustes — e consome a API em `http://127.0.0.1:8080` por omissão.

Em **Resumo** há gráficos de receitas/despesas por mês (incluindo os meses previstos) e a rosca de despesas por categoria do mês corrente. Em **Lançamentos** dá para editar (toque na linha), selecionar vários para apagar de uma vez e desfazer uma importação inteira pela tela de importação. Em **Regras**, o botão de lixeira no cabeçalho de cada categoria apaga a categoria inteira e recategoriza os lançamentos pelas regras restantes. Em **Ajustes** é possível trocar o endereço do servidor e informar o `API_TOKEN` (deixe vazio quando o backend roda em `development`, onde o token não é exigido), além do "Apagar tudo" com escolha de escopo — só lançamentos e importações, também as contas, ou tudo inclusive as regras.

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
| `DELETE` | `/api/transactions/:id` | — | `204` |
| `DELETE` | `/api/transactions` | `BulkDeleteRequest` (`ids`) | `BulkDeleteResponse` |
| `POST` | `/api/imports` | `ImportRequestDTO` | `ImportReportDTO` (com o `batchID` do lote) |
| `GET` | `/api/imports` | — | `[ImportBatchDTO]` |
| `DELETE` | `/api/imports/:batchID` | — | `BulkDeleteResponse` (desfaz a importação) |
| `DELETE` | `/api/categories/:category` | — | `DeleteCategoryResponse` (apaga as regras e recategoriza os lançamentos) |
| `POST` | `/api/reset` | `ResetRequest` (`scope` + `confirmation: "APAGAR TUDO"`) | `ResetResponse` com o que foi apagado |
| `GET` | `/api/summary` | — | `MonthlySummary` por mês, com os meses projetados |

`GET /api/transactions` aceita os filtros `accountID`, `from`, `to` (por dia inteiro), `search`, `includeProjected`, `limit` (máx. 1000) e `offset`.

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
As datas trafegam em ISO-8601. `category` é opcional; quando omitida o servidor aplica as regras e, sem correspondência, grava `"Geral"`. `isProjected` marca parcelas futuras ainda não confirmadas pela fatura, e `dedupKey` é atribuída pelo servidor (somente leitura).

### Importação

`POST /api/imports` recebe o extrato em texto (`ImportRequestDTO`: `accountID`, `content`, `filename`, `format`, `expandInstallments`). O formato (CSV ou OFX) é detectado pelo conteúdo, contas do tipo `creditCard` expandem as parcelas futuras como lançamentos projetados, e lançamentos já existentes são ignorados pela chave de deduplicação — o relatório devolve `imported`, `duplicates`, `projectedInstallments`, `confirmedInstallments`, `failures` e o `batchID` usado para desfazer.

---

## 🧪 Testes

```zsh
cd Kaus-Media && swift test
cd ../Kaus-Australis && swift test
```
