import SwiftUI
import KausMedia

/// Bolinhas com as cores de destaque; a escolhida leva um check.
struct AccentPicker: View {
    @Binding var selection: AppAccent

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppAccent.allCases) { option in
                Button {
                    selection = option
                } label: {
                    Circle()
                        .fill(option.color.gradient)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .help(option.title)
            }
        }
    }
}

/// Cartão de seção dos Ajustes: ícone colorido, título, explicação opcional.
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let color: Color
    var subtitle: String?
    var isDanger = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: symbol, color: color, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .card()
        .overlay {
            if isDanger {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.45), lineWidth: 1)
            }
        }
    }
}

/// Miniatura do tema: um pedacinho da tela no claro, no escuro ou dividida.
struct ThemeTile: View {
    let option: AppAppearance
    let isSelected: Bool
    let action: () -> Void

    private let light = Color(hex: 0xF4F1EA)
    private let dark = Color(hex: 0x0A0F1F)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Palette.hairline), lineWidth: isSelected ? 2 : 1)
                    )
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    }
                    Text(option.title)
                }
                .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        switch option {
        case .light: sample(background: light, line: Color(hex: 0xE2DCCF))
        case .dark: sample(background: dark, line: Color(hex: 0x26304F))
        case .system:
            HStack(spacing: 0) {
                sample(background: light, line: Color(hex: 0xE2DCCF))
                sample(background: dark, line: Color(hex: 0x26304F))
            }
        }
    }

    private func sample(background: Color, line: Color) -> some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Palette.star).frame(width: 22, height: 5)
                Capsule().fill(line).frame(width: 40, height: 5)
                Capsule().fill(line).frame(width: 30, height: 5)
            }
            .padding(10)
        }
    }
}

/// Contador dos dados guardados no servidor.
struct StatTile: View {
    let title: String
    let value: Int
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
