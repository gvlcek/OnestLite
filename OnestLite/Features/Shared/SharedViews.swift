import SwiftUI

struct MessageBanner: View {
    enum Style { case error, info }

    let text: String
    var style: Style = .error

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: style == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .foregroundStyle(style == .error ? Color.red : Color.blue)
        .background((style == .error ? Color.red : Color.blue).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    let status: LoanStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .enRevision: return .orange
        case .aprobado: return .blue
        case .desembolsado: return .green
        case .rechazado: return .red
        case .pagado: return .gray
        }
    }
}

struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
