import SwiftUI
import KausMedia

/// Tema escolhido em Ajustes; `system` segue o modo claro/escuro do aparelho.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Cor de destaque escolhida em Ajustes: botões, seleção e o cartão de patrimônio.
enum AppAccent: String, CaseIterable, Identifiable {
    case amber
    case indigo
    case blue
    case teal
    case green
    case orange
    case red
    case pink
    case purple

    static let storageKey = "accent"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .amber: return Palette.star
        case .indigo: return .indigo
        case .blue: return .blue
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        }
    }

    var title: String {
        switch self {
        case .amber: return "Âmbar"
        case .indigo: return "Índigo"
        case .blue: return "Azul"
        case .teal: return "Turquesa"
        case .green: return "Verde"
        case .orange: return "Laranja"
        case .red: return "Vermelho"
        case .pink: return "Rosa"
        case .purple: return "Roxo"
        }
    }
}

// MARK: - Estrutura das telas
