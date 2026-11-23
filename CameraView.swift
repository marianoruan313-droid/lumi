import SwiftUI
import AVFoundation

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: PhotoStore
    @StateObject private var camera = CameraService()
    @State private var profile: CameraProfile
    @State private var saveMode: SaveMode = .both
    @State private var showPicker = false
    @State private var showGrid = false
    @State private var flashFX = false
    @State private var status: String?
    @State private var focusPoint: CGPoint?
    @State private var ev: Double = 0
    @State private var zoomBase: CGFloat = 1
    @State private var timer = 0
    @State private var countdown = 0

    init(profile: CameraProfile) { _profile = State(initialValue: profile) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                previewArea
                Spacer(minLength: 0)
                controls
            }
            if countdown > 0 { Text("\(countdown)").font(.system(size: 120, weight: .thin)).foregroundStyle(.white) }
            Color.white.opacity(flashFX ? 0.8 : 0).ignoresSafeArea().allowsHitTesting(false)
        }
        .onAppear {
            camera.previewProfile = profile
            camera.onPhoto = { handle($0) }
            camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: profile) { camera.previewProfile = $0 }
        .sheet(isPresented: $showPicker) { picker }
        .alert("Lumi", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
            Button("OK") { status = nil }
        } message: { Text(status ?? "") }
    }

    // MARK: Partes

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark") }
            Spacer()
            Button { showPicker = true } label: {
                Text(profile.name).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8).background(.white.opacity(0.12), in: Capsule())
            }
            Spacer()
            if camera.flashSupported {
                Button { cycleFlash() } label: { Image(systemName: flashIcon) }
            } else { Image(systemName: "bolt.slash").opacity(0.3) }
        }
        .padding().foregroundStyle(.white)
    }

    private var previewArea: some View {
        ZStack {
            CameraPreview(session: camera.session, onTap: { dev, pt in
                camera.focus(at: dev, lock: false); focusPoint = pt
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { focusPoint = nil }
            })
            if let cg = camera.previewImage {
                Image(decorative: cg, scale: 1).resizable().scaledToFill().allowsHitTesting(false)
            }
            if showGrid { GridOverlay().stroke(.white.opacity(0.4), lineWidth: 0.5).allowsHitTesting(false) }
            if let p = focusPoint {
                RoundedRectangle(cornerRadius: 4).stroke(.yellow, lineWidth: 1.5)
                    .frame(width: 70, height: 70).position(p).allowsHitTesting(false)
            }
            switch camera.state {
            case .denied: Text("Permita o acesso à câmera em Ajustes › Lumi.").multilineTextAlignment(.center).padding()
            case .unavailable: Text("Câmera indisponível neste aparelho.").padding()
            case .failed(let m): Text(m).padding()
            default: EmptyView()
            }
        }
        .aspectRatio(profile.aspect.ratio, contentMode: .fit)
        .clipped()
        .gesture(MagnificationGesture()
            .onChanged { camera.setZoom(zoomBase * $0) }
            .onEnded { _ in zoomBase = camera.currentZoom })
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Text("EV").font(.caption2)
                Slider(value: $ev, in: -2...2, step: 0.1).onChange(of: ev) { camera.setExposureBias(Float($0)) }
                Text(String(format: "%+.1f", ev)).font(.caption.monospacedDigit()).frame(width: 36)
            }
            HStack(spacing: 22) {
                Menu {
                    Picker("Formato", selection: $profile.aspect) { ForEach(AspectOption.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Text(profile.aspect.rawValue).font(.footnote.weight(.semibold)) }
                Button { timer = [0, 3, 10][([0, 3, 10].firstIndex(of: timer)! + 1) % 3] } label: {
                    Image(systemName: timer == 0 ? "timer" : "timer.circle.fill"); if timer > 0 { Text("\(timer)s").font(.caption) }
                }
                Button { showGrid.toggle() } label: { Image(systemName: showGrid ? "grid.circle.fill" : "grid") }
                Menu {
                    Picker("Salvar", selection: $saveMode) { ForEach(SaveMode.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Image(systemName: "square.and.arrow.down") }
            }
            HStack {
                Spacer().frame(width: 60)
                Spacer()
                shutter
                Spacer()
                Button { camera.flip() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2) }
                    .frame(width: 60)
            }
        }
        .padding().foregroundStyle(.white)
    }

    private var shutter: some View {
        Button { shoot() } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(.white).frame(width: camera.isCapturing ? 56 : 64, height: camera.isCapturing ? 56 : 64)
            }
        }
        .animation(.easeOut(duration: 0.12), value: camera.isCapturing)
        .disabled(camera.state != .running || countdown > 0)
    }

    private var picker: some View {
        NavigationStack {
            List(ProfileLibrary.all) { p in
                Button { profile = p; showPicker = false } label: {
                    VStack(alignment: .leading) { Text(p.name).font(.headline); Text(p.tagline).font(.caption).foregroundStyle(.secondary) }
                }
            }.navigationTitle("Trocar câmera")
        }.presentationDetents([.medium, .large])
    }

    // MARK: Ações

    private var flashIcon: String {
        switch camera.flashMode { case .on: return "bolt.fill"; case .auto: return "bolt.badge.a"; default: return "bolt.slash" }
    }

    private func cycleFlash() {
        camera.flashMode = camera.flashMode == .off ? .auto : (camera.flashMode == .auto ? .on : .off)
    }

    private func shoot() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard timer > 0 else { camera.capture(); return }
        countdown = timer
        Task {
            while countdown > 0 { try? await Task.sleep(nanoseconds: 1_000_000_000); countdown -= 1 }
            camera.capture()
        }
    }

    private func handle(_ data: Data) {
        flashFX = true
        withAnimation(.easeOut(duration: 0.25)) { flashFX = false }
        let p = profile, mode = saveMode
        Task {
            do { _ = try await store.ingest(originalData: data, profile: p, mode: mode, saveToPhotos: true) }
            catch { status = error.localizedDescription }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onTap: (CGPoint, CGPoint) -> Void   // (ponto do dispositivo, ponto na view)

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        context.coordinator.view = v
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) { context.coordinator.onTap = onTap }
    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        var onTap: (CGPoint, CGPoint) -> Void
        weak var view: PreviewUIView?
        init(onTap: @escaping (CGPoint, CGPoint) -> Void) { self.onTap = onTap }
        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = view else { return }
            let pt = g.location(in: v)
            onTap(v.previewLayer.captureDevicePointConverted(fromLayerPoint: pt), pt)
        }
    }
}

struct GridOverlay: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 1...2 {
            let x = r.width * CGFloat(i) / 3, y = r.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: r.height))
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: r.width, y: y))
        }
        return p
    }
}
