import SwiftUI
import PhotosUI
import UIKit

/// Compose sheet for new tweets and replies. Reuses HubClient.publishTweet,
/// which signs the envelope with the keychain-resident app key. Image
/// attachments go through /v1/upload first; the resulting `media:<hash>`
/// embeds ride along on the published TWEET_ADD envelope.
struct ComposeTweetView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var parentHash: String?
    var channelId: String?
    var onPublished: ((String) -> Void)?

    @State private var text: String = ""
    @State private var posting = false
    @State private var error: String?

    @State private var pickerSelections: [PhotosPickerItem] = []
    /// Loaded image bytes + the JPEG MIME type we'll upload as. Kept
    /// out of `pickerSelections` so a user can drop one of the
    /// chosen photos before publish without rerunning the load.
    @State private var attachments: [Attachment] = []
    /// Per-image upload error surfaced inline; main `error` is for
    /// publish-side failures.
    @State private var uploadError: String?

    private static let maxChars = 280
    private static let maxAttachments = 4

    private var charsLeft: Int { Self.maxChars - text.count }
    private var canPost: Bool {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
        return hasContent
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

                if !attachments.isEmpty {
                    attachmentStrip
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                if let uploadError {
                    Label(uploadError, systemImage: "photo.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $pickerSelections,
                        maxSelectionCount: Self.maxAttachments - attachments.count,
                        matching: .images
                    ) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(attachments.count >= Self.maxAttachments ? Color.tertiaryLabel : .accentColor)
                    }
                    .disabled(attachments.count >= Self.maxAttachments)
                    .accessibilityLabel("Attach images")

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
            .onChange(of: pickerSelections) { _, items in
                Task { await loadPickedItems(items) }
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { att in
                    ZStack(alignment: .topTrailing) {
                        if let img = UIImage(data: att.data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
                                .frame(width: 88, height: 88)
                        }
                        Button {
                            attachments.removeAll { $0.id == att.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .black.opacity(0.65))
                                .padding(4)
                        }
                        .accessibilityLabel("Remove image")
                    }
                }
            }
        }
    }

    @MainActor
    private func loadPickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        uploadError = nil
        var loaded: [Attachment] = []
        for item in items {
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else { continue }
                guard let downscaled = downscale(raw) else { continue }
                loaded.append(Attachment(data: downscaled))
            } catch {
                uploadError = "Couldn't load image: \(error.localizedDescription)"
            }
        }
        let room = max(0, Self.maxAttachments - attachments.count)
        attachments.append(contentsOf: loaded.prefix(room))
        // Reset selection so picking the *same* photo again still
        // triggers an onChange.
        pickerSelections = []
    }

    /// Re-encode to JPEG at a max edge of 1600 px to stay comfortably
    /// under the hub's 5 MB ceiling. Anything that already fits and
    /// is smaller than the cap goes through unchanged at quality 0.85.
    private func downscale(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let maxEdge: CGFloat = 1600
        let longest = max(img.size.width, img.size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }

    private func post() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        posting = true
        error = nil
        defer { posting = false }
        do {
            // Upload every attached image first; turn each returned
            // hash into the embed reference the hub stores on the
            // tweet row. resolveMediaURL on the read side rebuilds
            // the absolute URL against the current hub.
            var embeds: [String] = []
            for att in attachments {
                let hash = try await app.api.uploadMedia(data: att.data, contentType: "image/jpeg")
                embeds.append("media:\(hash)")
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let hash = try await app.api.publishTweet(
                text: trimmed,
                as: key,
                tid: tid,
                parentHash: parentHash,
                channelId: channelId,
                embeds: embeds.isEmpty ? nil : embeds
            )
            onPublished?(hash)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct Attachment: Identifiable, Hashable {
    let id = UUID()
    let data: Data
}

private extension Color {
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
}
