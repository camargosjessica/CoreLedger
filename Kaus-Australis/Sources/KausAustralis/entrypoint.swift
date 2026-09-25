import Vapor
import KausMedia

// 💡 O Pulo do Gato: Ensinamos o Vapor que o DTO do nosso pacote compartilhado 
// pode ser convertido para JSON na rede, sem sujar o pacote original!
extension TransactionDTO: Content {}

@main
struct App {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        // Inicialização moderna (totalmente assíncrona)
        let app = try await Application.make(env)
        
        // Rota de Health Check
        app.get("health") { req async -> String in
            return "Kaus Australis (Backend) está online e respirando! 🚀"
        }

        // Rota testando o Kaus-Media
        app.get("api", "test-transaction") { req async -> TransactionDTO in
            return TransactionDTO(
                description: "Setup do Servidor CoreLedger",
                amount: 0.0,
                date: Date(),
                category: "Infraestrutura"
            )
        }

        // Executa o servidor e limpa a memória ao desligar
        try await app.execute()
        try await app.asyncShutdown()
    }
}
