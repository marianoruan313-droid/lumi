import Foundation

enum CameraCategory: String, Codable, CaseIterable, Identifiable {
    case digicam = "Digicam", ccd = "CCD", film = "Film", instant = "Instant", flash = "Flash", night = "Night", portrait = "Portrait"
    var id: String { rawValue }
}

enum AspectOption: String, Codable, CaseIterable, Identifiable {
    case r4x3 = "4:3", r3x2 = "3:2", r16x9 = "16:9", r1x1 = "1:1", r9x16 = "9:16"
    var id: String { rawValue }
    var ratio: Double { switch self { case .r4x3: return 4.0/3.0; case .r3x2: return 3.0/2.0; case .r16x9: return 16.0/9.0; case .r1x1: return 1; case .r9x16: return 9.0/16.0 } }
}

enum FrameStyle: String, Codable, CaseIterable, Identifiable { case none, white, black, instant; var id: String { rawValue } }
enum FlashLook: String, Codable, CaseIterable, Identifiable {
    case none, direct, party, soft
    var id: String { rawValue }
    var look: (bg: Double, center: Double, warmth: Double, contrast: Double) {
        switch self { case .none: return (0,0,0,0); case .direct: return (0.12,0.20,120,0.08); case .party: return (0.28,0.30,180,0.16); case .soft: return (0.05,0.10,80,0.02) }
    }
}

struct CameraProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var tagline: String
    var category: CameraCategory
    var era: String
    var lens: String
    var exposure: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var temperature: Double = 0
    var tint: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var blackPoint: Double = 0
    var curve: [Double] = [0, 0.25, 0.5, 0.75, 1]
    var grain: Double = 0
    var grainSize: Double = 1
    var sharpness: Double = 0
    var bloom: Double = 0
    var halation: Double = 0
    var vignette: Double = 0
    var flash: FlashLook = .none
    var flashIntensity: Double = 0
    var aspect: AspectOption = .r4x3
    var frame: FrameStyle = .none
}
