import Foundation

struct InputSelection: Codable, Identifiable, Sendable {
    var id = UUID()
    var deviceUID = ""
    var name = "未选择设备"
    var gain: Double = 0.7
    var muted = false
}

struct MixerSettings: Codable, Sendable {
    var inputs: [InputSelection] = []
    var masterGain: Double = 0.75
    var startOnLaunch = true
    var captureOnDemand = true

    private enum CodingKeys: String, CodingKey {
        case inputs, masterGain, startOnLaunch, captureOnDemand
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inputs = try values.decodeIfPresent([InputSelection].self, forKey: .inputs) ?? []
        masterGain = try values.decodeIfPresent(Double.self, forKey: .masterGain) ?? 0.75
        startOnLaunch = try values.decodeIfPresent(Bool.self, forKey: .startOnLaunch) ?? true
        captureOnDemand = try values.decodeIfPresent(Bool.self, forKey: .captureOnDemand) ?? true
    }
}
