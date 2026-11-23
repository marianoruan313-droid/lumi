import Foundation
import Combine
import CoreImage
import Photos
import ImageIO
import UIKit

enum SaveMode: String, Codable, CaseIterable, Identifiable {
    case original = "Save Original", effect = "Save Camera Effect", both = "Save Both"
    var id: String { rawValue }
}

struct CaptureRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var profile: CameraProfile        // snapshot, permite reprocessar depois
    var originalFile: String
    var processedFile: String?
}

/// Guarda o original (sempre, antes de processar) + versão processada + registro JSON no sandbox do app.
@MainActor
final class PhotoStore: ObservableObject {
    @Published private(set) var records: [CaptureRecord] = []
    private let dir: URL
    private let pipeline = ProcessingPipeline()

    init(directory: URL? = nil) {
        dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Captures")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    var indexURL: URL { dir.appendingPathComponent("index.json") }
    func url(_ file: String) -> URL { dir.appendingPathComponent(file) }

    private func load() {
        guard let d = try? Data(contentsOf: indexURL),
              let r = try? JSONDecoder().decode([CaptureRecord].self, from: d) else { return }
        records = r.sorted { $0.date > $1.date }
    }

    private func persist() throws {
        let d = try JSONEncoder().encode(records)
        try d.write(to: indexURL, options: .atomic)
    }

    /// 1) grava o original, 2) processa em resolução total, 3) grava processada, 4) só então confirma.
    func ingest(originalData: Data, profile: CameraProfile, mode: SaveMode, saveToPhotos: Bool) async throws -> CaptureRecord {
        let id = UUID()
        let origName = "\(id.uuidString)_orig.heic"
        try originalData.write(to: url(origName), options: .atomic)

        var procName: String?
        var processedData: Data?
        if mode != .original {
            let pipe = pipeline
            processedData = try await Task.detached(priority: .userInitiated) { () -> Data in
                guard let src = CIImage(data: originalData, options: [.applyOrientationProperty: true]) else {
                    throw StoreError.decodeFailed
                }
                let out = pipe.process(src, profile: profile, mode: .full)
                guard let data = pipe.encodeHEIF(out) else { throw StoreError.encodeFailed }
                return data
            }.value
            procName = "\(id.uuidString)_proc.heic"
            try processedData!.write(to: url(procName!), options: .atomic)
        }
        let rec = CaptureRecord(id: id, date: Date(), profile: profile, originalFile: origName, processedFile: procName)
        records.insert(rec, at: 0)
        try persist()

        if saveToPhotos {
            var toSave: [Data] = []
            if mode == .original || mode == .both { toSave.append(originalData) }
            if mode != .original, let p = processedData { toSave.append(p) }
            try await Self.saveToLibrary(toSave)
        }
        return rec
    }

    /// Reprocessa o original com outro perfil (não destrutivo).
    func reprocess(_ rec: CaptureRecord, with profile: CameraProfile) async throws {
        let originalData = try Data(contentsOf: url(rec.originalFile))
        let pipe = pipeline
        let data = try await Task.detached(priority: .userInitiated) { () -> Data in
            guard let src = CIImage(data: originalData, options: [.applyOrientationProperty: true]) else { throw StoreError.decodeFailed }
            guard let d = pipe.encodeHEIF(pipe.process(src, profile: profile, mode: .full)) else { throw StoreError.encodeFailed }
            return d
        }.value
        let name = rec.processedFile ?? "\(rec.id.uuidString)_proc.heic"
        try data.write(to: url(name), options: .atomic)
        if let i = records.firstIndex(of: rec) {
            records[i].profile = profile; records[i].processedFile = name
            try persist()
        }
    }

    func delete(_ rec: CaptureRecord) {
        try? FileManager.default.removeItem(at: url(rec.originalFile))
        if let p = rec.processedFile { try? FileManager.default.removeItem(at: url(p)) }
        records.removeAll { $0.id == rec.id }
        try? persist()
    }

    func thumbnail(_ file: String, maxPixel: Int = 400) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url(file) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map(UIImage.init(cgImage:))
    }

    func image(_ file: String) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url(file) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2400]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map(UIImage.init(cgImage:))
    }

    enum StoreError: LocalizedError {
        case decodeFailed, encodeFailed, photosDenied
        var errorDescription: String? {
            switch self {
            case .decodeFailed: return "Não foi possível ler a foto original."
            case .encodeFailed: return "Falha ao gerar a foto processada. O original foi preservado."
            case .photosDenied: return "Sem permissão para salvar na biblioteca. As fotos ficaram na galeria do app."
            }
        }
    }

    nonisolated static func saveToLibrary(_ items: [Data]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw StoreError.photosDenied }
        try await PHPhotoLibrary.shared().performChanges {
            for d in items {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: d, options: nil)
            }
        }
    }
}

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var ids: Set<String>
    private let key = "lumi.favorites"
    init() { ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
