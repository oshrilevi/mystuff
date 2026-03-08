#if os(macOS)
import SwiftUI
import AppKit
import AVFoundation

/// Presents the Mac camera with a live preview. User can take a photo or cancel.
struct MacCameraCaptureView: View {
    @Binding var capturedImageData: Data?
    var onDismiss: () -> Void

    @StateObject private var capture = MacCameraCaptureModel()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraPreviewView(session: capture.session)
                    .background(Color.black)

                if let message = capture.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(message)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 300)

            HStack(spacing: 16) {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    capture.capturePhoto { data in
                        capturedImageData = data
                        onDismiss()
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(capture.errorMessage != nil || capture.isCapturing)
            }
            .padding()
        }
        .frame(width: 520, height: 420)
        .onAppear {
            capture.startSession()
        }
        .onDisappear {
            capture.stopSession()
        }
    }
}

// MARK: - Preview NSView

private struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> NSView {
        let view = CameraPreviewNSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CameraPreviewNSView else { return }
        view.previewLayer?.session = session
    }
}

private final class CameraPreviewNSView: NSView {
    override var layer: CALayer? {
        get { super.layer }
        set { super.layer = newValue }
    }

    override func makeBackingLayer() -> CALayer {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspect
        return layer
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

// MARK: - Capture model

private final class MacCameraCaptureModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published var errorMessage: String?
    @Published var isCapturing = false

    private let sessionQueue = DispatchQueue(label: "MacCameraCapture.session")
    private var photoCompletion: ((Data?) -> Void)?

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async {
                self.errorMessage = "No camera found."
            }
            return
        }

        guard device.hasMediaType(.video) else {
            DispatchQueue.main.async {
                self.errorMessage = "Device does not support video."
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            return
        }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        DispatchQueue.main.async {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async {
                        self?.session.startRunning()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Camera access was denied. Enable it in System Settings → Privacy & Security → Camera."
                    }
                }
            }
        }
    }

    func capturePhoto(completion: @escaping (Data?) -> Void) {
        guard session.isRunning else {
            completion(nil)
            return
        }
        photoCompletion = completion
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        if let output = session.outputs.first(where: { $0 is AVCapturePhotoOutput }) as? AVCapturePhotoOutput {
            output.capturePhoto(with: settings, delegate: self)
        } else {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.photoCompletion?(nil)
                self.photoCompletion = nil
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            self.isCapturing = false
            self.photoCompletion?(data)
            self.photoCompletion = nil
        }
    }
}
#endif
