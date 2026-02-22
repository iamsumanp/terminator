import SwiftUI

struct HistoryDropdownView: View {
    let sessions: [ChatSession]
    let currentSessionID: UUID
    let onSelect: (UUID) -> Void
    let onNewSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Button("New Session") {
                    onNewSession()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider().overlay(.white.opacity(0.12))

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sessions) { session in
                        Button {
                            onSelect(session.id)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(.white.opacity(0.9))
                                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                if currentSessionID == session.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white.opacity(0.95))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(currentSessionID == session.id ? Color.blue.opacity(0.35) : Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 330, height: 380)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    }
}
