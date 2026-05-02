import SwiftUI
import AppKit

/// Apple-Health-aesthetic card surface: rounded corners, ultra-thin material fill,
/// hairline border, soft drop shadow. Auto-adapts dark/light via semantic colors.
struct HealthCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 1)
    }
}

extension View {
    func healthCard(padding: CGFloat = 16, cornerRadius: CGFloat = 16) -> some View {
        modifier(HealthCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

/// Header used at the top of every dashboard card: SF symbol + uppercase title +
/// optional info button (clickable popover + native tooltip on hover).
struct CardHeader: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var info: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .default))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            if let info {
                InfoIcon(text: info, tint: tint)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Tiny accent-colored (i) circle. Click = popover with the explanation.
/// Hover = system tooltip + pointing-hand cursor for clear affordance.
struct InfoIcon: View {
    let text: String
    var tint: Color = .accentColor

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? tint : Color.secondary.opacity(0.7))
                .contentShape(Rectangle())
                .padding(.horizontal, 1)
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel("About this metric")
        .accessibilityHint(text)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 300, alignment: .leading)
        }
    }
}
