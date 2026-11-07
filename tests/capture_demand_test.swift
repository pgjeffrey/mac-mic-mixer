import Foundation

@main
struct CaptureDemandTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() throws {
        var demand = CaptureDemand()
        check(!demand.wantsCapture(armed: true, onDemand: true, clientInUse: false,
                                  capturing: false, now: 0), "Opening the app must remain idle")
        check(demand.wantsCapture(armed: true, onDemand: true, clientInUse: true,
                                 capturing: false, now: 1), "A reader must activate capture immediately")
        check(demand.wantsCapture(armed: true, onDemand: true, clientInUse: false,
                                 capturing: true, now: 2), "Brief reader gaps should retain capture")
        check(demand.wantsCapture(armed: true, onDemand: true, clientInUse: true,
                                 capturing: true, now: 2.5), "An arriving reader must cancel idle release")
        check(demand.wantsCapture(armed: true, onDemand: true, clientInUse: false,
                                 capturing: true, now: 3), "A new gap must start its own grace period")
        check(!demand.wantsCapture(armed: true, onDemand: true, clientInUse: false,
                                  capturing: true, now: 4), "The last reader leaving must release capture")
        check(!demand.wantsCapture(armed: false, onDemand: true, clientInUse: true,
                                  capturing: true, now: 5), "Explicit stop must override active readers")
        check(!demand.wantsCapture(armed: true, onDemand: true, clientInUse: nil,
                                  capturing: true, now: 6), "Unknown demand must release capture")
        check(demand.wantsCapture(armed: true, onDemand: true, clientInUse: true,
                                 capturing: false, now: 7), "Demand recovery must reactivate capture")
        check(demand.wantsCapture(armed: true, onDemand: false, clientInUse: false,
                                 capturing: false, now: 8), "Continuous mode must preserve manual capture")
        check(!demand.wantsCapture(armed: false, onDemand: false, clientInUse: true,
                                  capturing: true, now: 9), "Stop must also release continuous mode")

        let id = UUID()
        let old = """
        {"inputs":[{"id":"\(id.uuidString)","deviceUID":"saved-device","name":"Saved mic", "gain":0.42,"muted":true}],
         "masterGain":0.61,"startOnLaunch":false}
        """
        let migrated = try JSONDecoder().decode(MixerSettings.self, from: Data(old.utf8))
        check(migrated.captureOnDemand, "Existing settings must enable the requested on-demand default")
        check(migrated.inputs.first?.id == id && migrated.inputs.first?.deviceUID == "saved-device",
              "Migration must retain device identity")
        check(migrated.inputs.first?.gain == 0.42 && migrated.inputs.first?.muted == true,
              "Migration must retain per-input controls")
        check(migrated.masterGain == 0.61 && !migrated.startOnLaunch,
              "Migration must retain master gain and launch preference")
        var continuous = migrated
        continuous.captureOnDemand = false
        let encoded = try JSONEncoder().encode(continuous)
        let restored = try JSONDecoder().decode(MixerSettings.self, from: encoded)
        check(!restored.captureOnDemand && restored.inputs.first?.id == id,
              "Explicit continuous mode must survive saving and reopening")
        print("Demand activation, release grace, cancellation, unknown state, manual override and settings migration passed")
    }
}
