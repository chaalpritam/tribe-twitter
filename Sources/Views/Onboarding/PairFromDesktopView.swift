import SwiftUI
import TribeCore

/// Camera scanner that consumes a tribe-app pairing QR. On a successful
/// scan, swaps the hub URL and adopts the desktop's TID + app key —
/// AppState's phase recompute then routes to the main TabView.
struct PairFromDesktopView: View {
    @EnvironmentObject private var app: AppState
    @State private var error: String?
    @State private var working = false

    var body: some View {
        ZStack {
            QRScannerView(
                onScan: handle,
                onError: { error = $0 }
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                instructions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .navigationTitle("Scan QR")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var instructions: some View {
        VStack(spacing: 8) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.white)
            } else if working {
                ProgressView().tint(.white)
                Text("Signing in…")
                    .font(.footnote)
                    .foregroundStyle(.white)
            } else {
                Text("In tribe-app: open Settings → Log in on mobile, then point your camera at the QR.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func handle(_ raw: String) {
        guard !working else { return }
        working = true
        do {
            let payload = try PairingPayload.decode(raw)
            guard let url = URL(string: payload.hubUrl),
                  url.scheme == "http" || url.scheme == "https" else {
                throw PairingError.invalidHubURL
            }
            let key = try AppKey.restore(seedBase64: payload.appKeySeedB64)
            // Set the hub first so the main TabView starts fetching
            // against the right hub on phase flip.
            app.hubBaseURL = url
            try app.adopt(tid: payload.tid, appKey: key)
        } catch {
            self.error = error.localizedDescription
            working = false
        }
    }
}

private struct PairingPayload: Decodable {
    let v: Int
    let kind: String
    let tid: String
    let appKeySeedB64: String
    let hubUrl: String

    static func decode(_ raw: String) throws -> PairingPayload {
        guard let data = raw.data(using: .utf8) else { throw PairingError.notUTF8 }
        let payload: PairingPayload
        do {
            payload = try JSONDecoder().decode(PairingPayload.self, from: data)
        } catch {
            throw PairingError.unsupportedPayload
        }
        guard payload.v == 1, payload.kind == "tribe-pair" else {
            throw PairingError.unsupportedPayload
        }
        guard Int64(payload.tid) != nil else {
            throw PairingError.invalidTID
        }
        return payload
    }
}

private enum PairingError: LocalizedError {
    case notUTF8
    case unsupportedPayload
    case invalidTID
    case invalidHubURL

    var errorDescription: String? {
        switch self {
        case .notUTF8:            return "QR is not a valid pairing code."
        case .unsupportedPayload: return "QR is not a Tribe pairing code."
        case .invalidTID:         return "QR contains an invalid TID."
        case .invalidHubURL:      return "QR contains an invalid hub URL."
        }
    }
}
