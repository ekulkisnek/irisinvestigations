import Foundation
import AppKit
import CoreGraphics

/// C-compatible display reconfiguration callback; forwards to GammaController.shared.
private func displayReconfigurationCallback(_ displayID: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?) {
    GammaController.shared?.displayReconfiguration(display: displayID, flags: flags)
}

/// Manages display gamma (brightness + blue light reduction) via CoreGraphics. Applies the same tables to all connected displays.
final class GammaController {

    // MARK: - UserDefaults keys
    private enum Keys {
        static let brightness = "brightness"
        static let blueLight = "blueLight"
        static let enabled = "enabled"
    }

    // MARK: - State
    var brightness: Double {
        didSet { UserDefaults.standard.set(brightness, forKey: Keys.brightness) }
    }
    /// 0 = normal (100% blue light), 1 = max reduction (redscale: grayscale with red instead of white)
    var blueLightReduction: Double {
        didSet { UserDefaults.standard.set(blueLightReduction, forKey: Keys.blueLight) }
    }
    var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if isEnabled { startReapplyTimer() } else { stopReapplyTimer() }
        }
    }

    /// Original gamma tables per display (saved before first apply). Key: CGDirectDisplayID.
    private var originals: [CGDirectDisplayID: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue])] = [:]
    private var isReconfigurationRegistered = false

    // MARK: - Imperceptible slow drift (works with Night Shift, no visible on/off)
    private var pollTimer: Timer?
    private var isDrifting = false
    private var lastDriftEndTime: Date?
    private let driftCooldown: TimeInterval = 15.0
    private let pollInterval: TimeInterval = 2.0
    private var consecutiveDiffCount: Int = 0
    private let requiredConsecutiveDiffs = 2
    private let gammaDiffTolerance: Float = 0.06
    private let gammaCompareStride = 32
    /// No step may change any gamma value by more than this (keeps each step imperceptible).
    private let maxDeltaPerStep: Float = 0.006
    /// Wait this long after detecting overwrite before starting drift (avoids visible "fight" with Night Shift).
    private let delayBeforeDrift: TimeInterval = 6.0
    /// Time between drift steps.
    private let stepInterval: TimeInterval = 0.28
    /// Stop drifting when max absolute difference to target is below this.
    private let driftDoneTolerance: Float = 0.003
    private let maxDriftSteps = 500

    // MARK: - Init
    init() {
        self.brightness = UserDefaults.standard.object(forKey: Keys.brightness) as? Double ?? 0.7
        // Support old "warmth" key for migration; blueLight 0 = normal, 1 = redscale
        if let blue = UserDefaults.standard.object(forKey: Keys.blueLight) as? Double {
            self.blueLightReduction = blue
        } else if let w = UserDefaults.standard.object(forKey: "warmth") as? Double {
            self.blueLightReduction = w
        } else {
            self.blueLightReduction = 0
        }
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    // MARK: - Display enumeration
    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var displayIDs: [CGDirectDisplayID] = []
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(truncating: num)
            displayIDs.append(id)
        }
        return displayIDs
    }

    private func gammaTableCapacity(for displayID: CGDirectDisplayID) -> UInt32 {
        CGDisplayGammaTableCapacity(displayID)
    }

    // MARK: - Save originals (before first apply per display)
    private func saveOriginalsForDisplay(_ displayID: CGDirectDisplayID) {
        guard originals[displayID] == nil else { return }
        let capacity = gammaTableCapacity(for: displayID)
        guard capacity > 0 else { return }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0
        let err = CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &sampleCount)
        guard err == .success else { return }
        originals[displayID] = (red, green, blue)
    }

    /// Save originals for all currently online displays (call when user turns on).
    func saveOriginalsForAllCurrentDisplays() {
        for displayID in onlineDisplayIDs() {
            saveOriginalsForDisplay(displayID)
        }
    }

    // MARK: - Build R,G,B tables from brightness and blue light reduction
    /// Returns (red, green, blue) arrays. blueLightReduction 0 = normal, 1 = redscale (grayscale with red instead of white).
    private func buildTables(capacity: Int) -> (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) {
        let b = max(0, min(1, brightness))
        let blueRed = max(0, min(1, blueLightReduction))
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = [CGGammaValue](repeating: 0, count: capacity)
        var blue = [CGGammaValue](repeating: 0, count: capacity)
        let cap = Double(capacity)
        for i in 0..<capacity {
            let v = Double(i) / max(1, cap - 1)
            let dimmed = v * b
            // Red channel: full luminance (redscale = red only at max reduction)
            red[i] = CGGammaValue(min(1.0, dimmed))
            // Green and blue: scale by (1 - blueLightReduction); 0% = normal, 100% = no green/blue (redscale)
            let gbScale = 1.0 - blueRed
            green[i] = CGGammaValue(min(1.0, dimmed * gbScale))
            blue[i] = CGGammaValue(min(1.0, dimmed * gbScale))
        }
        return (red, green, blue)
    }

    /// True if the display’s current gamma differs from our target (e.g. Night Shift overwrote).
    private func currentGammaDiffersFromExpected(displayID: CGDirectDisplayID, capacity: Int) -> Bool {
        var curRed = [CGGammaValue](repeating: 0, count: capacity)
        var curGreen = [CGGammaValue](repeating: 0, count: capacity)
        var curBlue = [CGGammaValue](repeating: 0, count: capacity)
        var sampleCount: UInt32 = 0
        let err = CGGetDisplayTransferByTable(displayID, UInt32(capacity), &curRed, &curGreen, &curBlue, &sampleCount)
        guard err == .success else { return false }
        let (expRed, expGreen, expBlue) = buildTables(capacity: capacity)
        for i in stride(from: 0, to: capacity, by: gammaCompareStride) {
            if abs(curRed[i] - expRed[i]) > gammaDiffTolerance { return true }
            if abs(curGreen[i] - expGreen[i]) > gammaDiffTolerance { return true }
            if abs(curBlue[i] - expBlue[i]) > gammaDiffTolerance { return true }
        }
        return false
    }

    // MARK: - Apply to all displays
    func applyToAllDisplays() {
        let displayIDs = onlineDisplayIDs()
        guard let mainID = displayIDs.first else { return }
        let capacityInt = Int(gammaTableCapacity(for: mainID))
        guard capacityInt > 0 else { return }
        // Save originals for any new display we haven't seen
        for id in displayIDs {
            saveOriginalsForDisplay(id)
        }
        let (red, green, blue) = buildTables(capacity: capacityInt)
        let capacity = UInt32(capacityInt)
        for displayID in displayIDs {
            var r = red, g = green, b = blue
            let err = CGSetDisplayTransferByTable(displayID, capacity, &r, &g, &b)
            if err != .success { print("[ScreenWarmth] CGSetDisplayTransferByTable failed for display \(displayID): \(err.rawValue)") }
        }
    }

    // MARK: - Restore all displays
    func restoreAllDisplays() {
        let displayIDs = onlineDisplayIDs()
        for displayID in displayIDs {
            if let orig = originals[displayID] {
                var r = orig.red, g = orig.green, b = orig.blue
                CGSetDisplayTransferByTable(displayID, UInt32(orig.red.count), &r, &g, &b)
            }
        }
        // If we applied to displays we don't have originals for (e.g. connected after start),
        // they keep our gamma until next restart. CGDisplayRestoreColorSyncSettings() restores
        // all displays and takes no args, so we only restore from our saved originals.
        // Clear originals for displays no longer online to avoid leaking
        originals = originals.filter { displayIDs.contains($0.key) }
    }

    /// Restore our gamma with per-step delta cap so no single step is visible. Used when Night Shift overwrote us. Optional delay before starting avoids visible "fight" in same moment.
    private func slowDriftToTarget() {
        guard !isDrifting else { return }
        isDrifting = true
        let displayIDs = onlineDisplayIDs()
        guard displayIDs.first != nil else { isDrifting = false; return }
        let mainID = displayIDs.first!
        let capacityInt = Int(gammaTableCapacity(for: mainID))
        guard capacityInt > 0 else { isDrifting = false; return }
        for id in displayIDs { saveOriginalsForDisplay(id) }
        let target = buildTables(capacity: capacityInt)
        let capacity = UInt32(capacityInt)

        DispatchQueue.main.asyncAfter(deadline: .now() + delayBeforeDrift) { [weak self] in
            guard let self = self, self.isEnabled else {
                self?.isDrifting = false
                return
            }
            var currentPerDisplay: [CGDirectDisplayID: (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])] = [:]
            for displayID in displayIDs {
                var r = [CGGammaValue](repeating: 0, count: capacityInt)
                var g = [CGGammaValue](repeating: 0, count: capacityInt)
                var b = [CGGammaValue](repeating: 0, count: capacityInt)
                var sampleCount: UInt32 = 0
                let err = CGGetDisplayTransferByTable(displayID, capacity, &r, &g, &b, &sampleCount)
                guard err == .success else {
                    self.isDrifting = false
                    self.applyToAllDisplays()
                    return
                }
                currentPerDisplay[displayID] = (r, g, b)
            }

            var stepCount = 0
            func doStep() {
                guard self.isEnabled else {
                    self.isDrifting = false
                    return
                }
                stepCount += 1
                if stepCount > self.maxDriftSteps {
                    self.isDrifting = false
                    self.lastDriftEndTime = Date()
                    return
                }
                for displayID in displayIDs {
                    guard var cur = currentPerDisplay[displayID] else { continue }
                    for i in 0..<capacityInt {
                        let dr = Float(target.red[i]) - Float(cur.r[i])
                        cur.r[i] = CGGammaValue(Float(cur.r[i]) + max(-self.maxDeltaPerStep, min(self.maxDeltaPerStep, dr)))
                        let dg = Float(target.green[i]) - Float(cur.g[i])
                        cur.g[i] = CGGammaValue(Float(cur.g[i]) + max(-self.maxDeltaPerStep, min(self.maxDeltaPerStep, dg)))
                        let db = Float(target.blue[i]) - Float(cur.b[i])
                        cur.b[i] = CGGammaValue(Float(cur.b[i]) + max(-self.maxDeltaPerStep, min(self.maxDeltaPerStep, db)))
                    }
                    currentPerDisplay[displayID] = cur
                    var r = cur.r, g = cur.g, b = cur.b
                    CGSetDisplayTransferByTable(displayID, capacity, &r, &g, &b)
                }
                var maxDiff: Float = 0
                for displayID in displayIDs {
                    guard let cur = currentPerDisplay[displayID] else { continue }
                    for i in 0..<capacityInt {
                        maxDiff = max(maxDiff, abs(Float(cur.r[i]) - Float(target.red[i])), abs(Float(cur.g[i]) - Float(target.green[i])), abs(Float(cur.b[i]) - Float(target.blue[i])))
                    }
                }
                if maxDiff < self.driftDoneTolerance {
                    self.isDrifting = false
                    self.lastDriftEndTime = Date()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + self.stepInterval, execute: doStep)
            }
            doStep()
        }
    }

    // MARK: - Reconfiguration callback
    func displayReconfiguration(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        guard isEnabled else { return }
        applyToAllDisplays()
    }

    func registerReconfigurationCallback() {
        guard !isReconfigurationRegistered else { return }
        GammaController.shared = self
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)
        isReconfigurationRegistered = true
    }

    func unregisterReconfigurationCallback() {
        guard isReconfigurationRegistered else { return }
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
        isReconfigurationRegistered = false
        GammaController.shared = nil
    }

    // MARK: - Wake reapply (gamma fixer)
    func setupWakeNotification() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func workspaceDidWake() {
        guard isEnabled else { return }
        applyToAllDisplays()
    }

    // MARK: - Poll and imperceptible drift
    private func startReapplyTimer() {
        stopReapplyTimer()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isEnabled else { return }
            self.pollAndCorrectIfNeeded()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func stopReapplyTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// If gamma was overwritten (e.g. Night Shift), start a slow drift so we restore invisibly.
    private func pollAndCorrectIfNeeded() {
        if isDrifting { return }
        if let end = lastDriftEndTime, Date().timeIntervalSince(end) < driftCooldown { return }
        guard let mainID = onlineDisplayIDs().first else { return }
        let capacityInt = Int(gammaTableCapacity(for: mainID))
        guard capacityInt > 0 else { return }
        let differs = currentGammaDiffersFromExpected(displayID: mainID, capacity: capacityInt)
        if differs {
            consecutiveDiffCount += 1
            if consecutiveDiffCount >= requiredConsecutiveDiffs {
                consecutiveDiffCount = 0
                slowDriftToTarget()
            }
        } else {
            consecutiveDiffCount = 0
        }
    }

    func startReapplyTimerIfNeeded() {
        if isEnabled { startReapplyTimer() }
    }

    func applicationWillTerminate() {
        stopReapplyTimer()
    }

    /// Static reference for C callback (set during register, cleared on unregister).
    static weak var shared: GammaController?
}
