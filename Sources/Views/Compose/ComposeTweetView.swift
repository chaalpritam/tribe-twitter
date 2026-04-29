import SwiftUI

/// Compose sheet for new tweets and replies. Reuses HubClient.publishTweet,
/// which signs the envelope with the keychain-resident app key.
struct ComposeTweetView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var parentHash: String?
    var channelId: String?
    var onPublished: ((String) -> Void)?

    @State private var text: String = ""
    @State private var posting = false
    @State private var error: String?

    private static let maxChars = 280

    private var charsLeft: Int { Self.maxChars - text.count }
    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && charsLeft >= 0
            && !posting
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let parentHash {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left")
                        Text("Replying to ")
                        Text(parentHash.prefix(8) + "…")
                            .font(.system(.footnote, design: .monospaced))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(parentHash != nil ? "Post your reply…" : "What's happening?")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 17)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                HStack {
                    if let channelId {
                        Label("#\(channelId)", systemImage: "number")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(charsLeft)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(charsLeft < 0 ? .red : (charsLeft < 20 ? .orange : .secondary))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(Color(.systemBackground))
            .navigationTitle(parentHash != nil ? "Reply" : "New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await post() }
                    } label: {
                        if posting { ProgressView() } else {
                            Text(parentHash != nil ? "Reply" : "Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canPost)
                }
            }
        }
    }

    private func post() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        posting = true
        error = nil
        defer { posting = false }
        do {
            let hash = try await app.api.publishTweet(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                as: key,
                tid: tid,
                parentHash: parentHash,
                channelId: channelId
            )
            onPublished?(hash)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
