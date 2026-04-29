import SwiftUI
import AVFoundation

/// SwiftUI wrapper around AVFoundation's QR scanner. Calls `onScan`
/// once with the first decoded string, then stops dispatching — the
/// caller decides what to do (typically dismiss the view).
struct QRScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        let onError: (String) -> Void
        // One-shot. Without this we'd fire onScan repeatedly while the
        // QR stays in frame.
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !hasScanned,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr,
                  let value = obj.stringValue
            else { return }
            hasScanned = true
            onScan(value)
        }
    }

    final class ScannerViewController: UIViewController {
        weak var coordinator: Coordinator?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            requestAccessAndStart()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            startIfReady()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                // Off the main thread — startRunning/stopRunning block.
                let session = self.session
                DispatchQueue.global(qos: .userInitiated).async {
                    session.stopRunning()
                }
            }
        }

        private func requestAccessAndStart() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                setupSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if granted {
                            self.setupSession()
                        } else {
                            self.coordinator?.onError("Camera access denied.")
                        }
                    }
                }
            case .denied, .restricted:
                coordinator?.onError("Camera access denied. Enable it in Settings.")
            @unknown default:
                coordinator?.onError("Camera access unavailable.")
            }
        }

        private func setupSession() {
            guard let device = AVCaptureDevice.default(for: .video) else {
                coordinator?.onError("Camera unavailable.")
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    coordinator?.onError("Cannot use camera.")
                    return
                }
                session.addInput(input)

                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    coordinator?.onError("Cannot capture metadata.")
                    return
                }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(coordinator, queue: .main)
                output.metadataObjectTypes = [.qr]

                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = view.bounds
                view.layer.addSublayer(layer)
                preview = layer

                startIfReady()
            } catch {
                coordinator?.onError(error.localizedDescription)
            }
        }

        private func startIfReady() {
            guard preview != nil, !session.isRunning else { return }
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }
}
