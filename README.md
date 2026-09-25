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

### 2. Configurar e Executar o Backend (`Kaus-Australis`)
Navegue até à pasta do backend e execute o servidor:
```zsh
cd Kaus-Australis
swift run
