import Foundation

struct CaptureDemand {
    private var idleSince: TimeInterval?

    mutating func wantsCapture(armed: Bool, onDemand: Bool, clientInUse: Bool?,
                              capturing: Bool, now: TimeInterval) -> Bool {
        guard armed else { idleSince = nil; return false }
        guard onDemand else { idleSince = nil; return true }
        if clientInUse == true { idleSince = nil; return true }
        guard clientInUse == false, capturing else { idleSince = nil; return false }
        let inactiveAt = idleSince ?? now
        idleSince = inactiveAt
        return now - inactiveAt < 1
    }
}
