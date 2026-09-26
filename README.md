# CoreLedger 📊

O **CoreLedger** é uma aplicação *Full-Stack* desenvolvida inteiramente em **Swift**, concebida para a gestão e registo de transações financeiras. O projeto adota uma arquitetura de **monorepo modular**, garantindo a partilha rigorosa de contratos de dados entre o servidor e a aplicação cliente, sem duplicação de código.

---

## 🏗️ Arquitetura do Monorepo

O repositório está estruturado em três módulos principais:

*   **`Kaus-Media`**: Pacote Swift independente (`Swift Package`) que centraliza os contratos de dados e DTOs partilhados (`TransactionDTO`).
*   **`Kaus-Australis`**: O backend do sistema, construído com o framework **Vapor**, utilizando o ORM *Fluent* e **PostgreSQL** para persistência robusta de dados.
*   **`Kaus-Borealis`**: O frontend nativo desenvolvido em **SwiftUI** para ecossistemas Apple (iOS / macOS), consumindo diretamente a API REST do backend.

---

## 🚀 Tecnologias Utilizadas

*   **Linguagem:** Swift (Swift 5.9+ / Swift 6)
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

`TransactionDTO`:
```json
{
  "id": "1B0E1E6E-...",
  "description": "Compra Mercado",
  "amount": -150.50,
  "date": "2025-01-31T12:00:00Z",
  "category": "Alimentação"
}
```
`category` é opcional; quando omitida o servidor grava `"Geral"`.

---

## 🧪 Testes

```zsh
cd Kaus-Media && swift test
cd ../Kaus-Australis && swift test
```
