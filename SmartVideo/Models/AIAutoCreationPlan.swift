import Foundation

enum AIAutoCreationStyle: String, CaseIterable, Identifiable {
    case reels = "TikTok / Reels 9:16"
    case travel = "Du lịch / Kỷ niệm"
    case cinematic = "Điện ảnh / Story"
    var id: String { rawValue }
    var photoSeconds: Double {
        switch self {
        case .reels: return 2.5
        case .travel: return 3.2
        case .cinematic: return 4.2
        }
    }
    var videoSeconds: Double {
        switch self {
        case .reels: return 5
        case .travel: return 8
        case .cinematic: return 12
        }
    }
}

struct AIAutoCreationDecision: Identifiable {
    let id: UUID
    let sourceURL: URL
    let kind: ClipKind
    let photoPresetID: String?
    let autoEnhance: AutoEnhanceSettings
    let offsetSeconds: Double
    let duration: Double
    let description: String
}

struct AIAutoCreationPlan {
    let sourceIDs: [UUID]
    let decisions: [AIAutoCreationDecision]
    let style: AIAutoCreationStyle
    var title: String
    var description: String
    var usedGemini: Bool = false

    var totalApproximateSeconds: Double {
        decisions.reduce(0) { $0 + $1.duration }
    }
}
