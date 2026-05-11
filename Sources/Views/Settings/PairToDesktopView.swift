import SwiftUI
import CoreImage.CIFilterBuiltins

/// Inverse of `PairFromDesktopView`: shows a QR encoding this device's
/// identity so tribe-app on desktop can scan to sign in as the same
/// TID. Same `{ v:1, kind:"tribe-pair", tid, appKeySeedB64, hubUrl }`
/// envelope `PairingPayload.decode` consumes on the other end, so the
/// formats stay symmetric.
///
/// Gated behind a reveal toggle — the QR is the app-key seed plus the
/// TID, so anything that scans it can sign as you.
struct PairToDesktopView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var revealed = false
    @State private var qrImage: UIImage?
    @State private var payloadJSON: String?
    @State private var copiedJSON = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let tid = app.myTID {
                        LabeledContent("TID", value: tid)
                    }
                    LabeledContent("Hub", value: app.hubBaseURL.absoluteString)
                        .font(.footnote)
                } header: {
                    Text("This device")
                }

                Section {
                    if !revealed {
                        Button {
                            reveal()
                        } label: {
                            Label("Reveal QR code", systemImage: "qrcode")
                                .frame(maxWidth: .infinity)
                        }
                    } else if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 320, maxHeight: 320)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        if let payloadJSON {
                            Button {
                                UIPasteboard.general.string = payloadJSON
                                copiedJSON = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    await MainActor.run { copiedJSON = false }
                                }
                            } label: {
                                Label(
                                    copiedJSON ? "Copied" : "Copy as JSON",
                                    systemImage: copiedJSON ? "checkmark.circle.fill" : "doc.on.doc"
                                )
                            }
                            .foregroundStyle(copiedJSON ? .green : .accentColor)
                        }
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                } header: {
                    Text("Pairing code")
                } footer: {
                    Text("In tribe-app on desktop: open Settings → Sign in from mobile, then point your camera at this QR. Anyone who scans it can sign as you, so don't share it.")
                }

                if revealed {
                    Section {
                        Button("Hide") {
                            revealed = false
                            qrImage = nil
                            payloadJSON = nil
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sign in another device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func reveal() {
        error = nil
        guard let tid = app.myTID, let key = app.appKey else {
            error = "Sign in first."
            return
        }
        let payload: [String: Any] = [
            "v": 1,
            "kind": "tribe-pair",
            "tid": tid,
            "appKeySeedB64": key.seedBase64,
            "hubUrl": app.hubBaseURL.absoluteString,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys]
            ),
            let jsonString = String(data: data, encoding: .utf8)
        else {
            error = "Failed to encode pairing payload."
            return
        }
        guard let image = makeQRCode(from: data) else {
            error = "Failed to render QR."
            return
        }
        qrImage = image
        payloadJSON = jsonString
        revealed = true
    }

    /// CIQRCodeGenerator → upscale via CIAffineTransform so the QR
    /// renders crisp at any size. `interpolation(.none)` on the
    /// `Image` view preserves the pixel grid.
    private func makeQRCode(from data: Data) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // M = 15% error correction, good balance for a clean print
        // of a JSON payload that's ~250 bytes.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = output.transformed(by: scale)
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
