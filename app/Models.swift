import Foundation

struct InputDevice: Decodable, Identifiable, Sendable {
    let uid: String
    let name: String
    let channels: UInt32
    let sampleRate: Double
    var id: String { uid }
}

struct DeviceList: Decodable, Sendable {
    let inputs: [InputDevice]
    let driverInstalled: Bool
    let driverVersion: String
    let virtualName: String
}

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
}

struct InputStatus: Decodable, Sendable {
    let deviceUID: String
    let receiving: Bool
    let connected: Bool
    let peak: Float
    let muted: Bool
}

struct EngineStatus: Decodable, Sendable {
    let running: Bool
    let starting: Bool
    let outputReady: Bool
    let allReceiving: Bool
    let anyReceiving: Bool
    let outputPeak: Float
    let droppedFrames: UInt64
    let underrunFrames: UInt64
    let clippedFrames: UInt64
    let renderCallbacks: UInt64
    let inputs: [InputStatus]

    static let stopped = EngineStatus(running: false, starting: false, outputReady: false,
        allReceiving: false, anyReceiving: false, outputPeak: 0, droppedFrames: 0,
        underrunFrames: 0, clippedFrames: 0, renderCallbacks: 0, inputs: [])
}

struct ActionResult: Decodable, Sendable {
    let ok: Bool
    let error: String
}

// The C handle is confined to queue, including creation and destruction.
final class EngineWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macmicmixer.engine", qos: .userInitiated)
    private var engine: OpaquePointer?

    init() {
        queue.sync { engine = Bundle.main.bundlePath.withCString { mm_engine_create($0) } }
    }

    private func decode<T: Decodable>(_ pointer: UnsafeMutablePointer<CChar>?, as: T.Type) throws -> T {
        guard let pointer else { throw WorkerError.message("读取音频引擎状态失败") }
        defer { mm_free_string(pointer) }
        return try JSONDecoder().decode(T.self, from: Data(String(cString: pointer).utf8))
    }

    enum WorkerError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
    }

    func refresh(_ completion: @escaping @MainActor (Result<(DeviceList, EngineStatus), Error>) -> Void) {
        queue.async {
            let result = Result {
                let devices = try self.decode(mm_devices_json(), as: DeviceList.self)
                let status = try self.decode(mm_engine_snapshot(self.engine), as: EngineStatus.self)
                return (devices, status)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func start(_ settings: MixerSettings, completion: @escaping @MainActor (String?) -> Void) {
        queue.async {
            do {
                let text = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
                let result = try text.withCString { try self.decode(mm_engine_start(self.engine, $0), as: ActionResult.self) }
                DispatchQueue.main.async { completion(result.ok ? nil : result.error) }
            } catch { DispatchQueue.main.async { completion(error.localizedDescription) } }
        }
    }

    func controls(_ settings: MixerSettings) {
        queue.async {
            guard let data = try? JSONEncoder().encode(settings) else { return }
            String(decoding: data, as: UTF8.self).withCString { mm_engine_controls(self.engine, $0) }
        }
    }

    func stop(_ completion: @escaping @MainActor () -> Void = {}) {
        queue.async {
            mm_engine_stop(self.engine)
            DispatchQueue.main.async { completion() }
        }
    }

    func verify(_ completion: @escaping @MainActor (Result<ActionResult, Error>) -> Void) {
        queue.async {
            let result = Result { try self.decode(mm_engine_verify_loopback(self.engine), as: ActionResult.self) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func shutdown(_ completion: @escaping @MainActor () -> Void) {
        queue.async {
            mm_engine_destroy(self.engine)
            self.engine = nil
            DispatchQueue.main.async { completion() }
        }
    }
}
