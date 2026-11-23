import AVFoundation
import Combine
import CoreImage
import UIKit

/// Sessão de câmera real: preview ao vivo filtrado (leve) + captura em alta resolução via AVCapturePhotoOutput.
final class CameraService: NSObject, ObservableObject {
    enum State: Equatable { case idle, running, denied, unavailable, failed(String) }

    let session = AVCaptureSession()
    @Published private(set) var state: State = .idle
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var flashSupported = false
    @Published private(set) var maxZoom: CGFloat = 1
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published private(set) var isCapturing = false

    var onPhoto: ((Data) -> Void)?

    private let sessionQueue = DispatchQueue(label: "lumi.camera.session")
    private let videoQueue = DispatchQueue(label: "lumi.camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private let pipeline = ProcessingPipeline()
    private let lock = NSLock()
    private var _profile = ProfileLibrary.all[0]
    private var lastFrame = CFAbsoluteTime(0)

    var previewProfile: CameraProfile {
        get { lock.lock(); defer { lock.unlock() }; return _profile }
        set { lock.lock(); _profile = newValue; lock.unlock() }
    }

    // MARK: Ciclo de vida

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { ok ? self?.configureAndRun() : (self?.state = .denied) }
            }
        default: state = .denied
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
            name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    func stop() {
        sessionQueue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    @objc private func interrupted(_ n: Notification) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.input == nil, !self.configure(position: .back) {
                DispatchQueue.main.async { self.state = .unavailable }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.state = .running }
        }
    }

    private func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func configure(position: AVCaptureDevice.Position) -> Bool {
        guard let dev = device(for: position), let newInput = try? AVCaptureDeviceInput(device: dev) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        if let old = input { session.removeInput(old) }
        guard session.canAddInput(newInput) else { return false }
        session.addInput(newInput)
        input = newInput

        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if let dim = dev.activeFormat.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = dim
        }
        photoOutput.maxPhotoQualityPrioritization = .quality

        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }
        if let c = videoOutput.connection(with: .video) {
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            c.isVideoMirrored = (position == .front)
        }
        let supportsFlash = dev.hasFlash && photoOutput.supportedFlashModes.contains(.on)
        let zoom = min(dev.activeFormat.videoMaxZoomFactor, 10)
        DispatchQueue.main.async {
            self.position = position
            self.flashSupported = supportsFlash
            self.maxZoom = zoom
            if !supportsFlash { self.flashMode = .off }
        }
        return true
    }

    // MARK: Controles

    func flip() {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        sessionQueue.async { [weak self] in _ = self?.configure(position: next) }
    }

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let dev = self?.input?.device, (try? dev.lockForConfiguration()) != nil else { return }
            dev.videoZoomFactor = max(1, min(factor, min(dev.activeFormat.videoMaxZoomFactor, 10)))
            dev.unlockForConfiguration()
        }
    }

    var currentZoom: CGFloat { input?.device.videoZoomFactor ?? 1 }

    func focus(at devicePoint: CGPoint, lock: Bool) {
        sessionQueue.async { [weak self] in
            guard let dev = self?.input?.device, (try? dev.lockForConfiguration()) != nil else { return }
            if dev.isFocusPointOfInterestSupported {
                dev.focusPointOfInterest = devicePoint
                dev.focusMode = lock ? .autoFocus : .continuousAutoFocus
            }
            if dev.isExposurePointOfInterestSupported {
                dev.exposurePointOfInterest = devicePoint
                dev.exposureMode = lock ? .autoExpose : .continuousAutoExposure
            }
            dev.unlockForConfiguration()
        }
    }

    /// Compensação de exposição em EV (hardware real).
    func setExposureBias(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let dev = self?.input?.device, (try? dev.lockForConfiguration()) != nil else { return }
            dev.setExposureTargetBias(max(dev.minExposureTargetBias, min(ev, dev.maxExposureTargetBias)))
            dev.unlockForConfiguration()
        }
    }

    // MARK: Captura

    func capture() {
        guard state == .running, !isCapturing else { return }
        isCapturing = true
        let wantFlash = flashMode
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else { settings = AVCapturePhotoSettings() }
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            if self.flashSupported, self.photoOutput.supportedFlashModes.contains(wantFlash) {
                settings.flashMode = wantFlash
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async { self.isCapturing = false }
        if let error { DispatchQueue.main.async { self.state = .failed(error.localizedDescription) }; return }
        guard let data = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async { self.onPhoto?(data) }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrame > 1.0 / 24.0, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        var ci = CIImage(cvPixelBuffer: pb)
        let s = 900.0 / max(ci.extent.width, ci.extent.height)
        ci = ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
        var p = previewProfile
        p.frame = .none            // moldura só na foto final
        let out = pipeline.process(ci, profile: p, mode: .preview)
        if let cg = pipeline.render(out) { DispatchQueue.main.async { self.previewImage = cg } }
    }
}
