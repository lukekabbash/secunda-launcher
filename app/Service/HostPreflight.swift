import Foundation

enum HostPreflight {
    static let recommendedInstallBytes: Int64 = 40 * 1_024 * 1_024 * 1_024

    static func evaluate(
        operatingSystem: OperatingSystemVersion,
        isAppleSilicon: Bool,
        sourceRuntimeProbeSucceeded: Bool,
        freeDiskBytes: Int64,
        needsInstallSpace: Bool,
        lowPowerModeEnabled: Bool = false
    ) -> ComponentState {
        guard isAppleSilicon else {
            return .failed("Secunda requires an Apple-silicon Mac")
        }
        guard operatingSystem.majorVersion >= 15 else {
            return .failed("macOS 15 or newer is required")
        }
        guard sourceRuntimeProbeSucceeded else {
            return .warning("Apple silicon is ready; the compatibility runtime and Rosetta check did not complete")
        }
        if lowPowerModeEnabled {
            return .warning("Runtime ready · Low Power Mode is limiting game performance")
        }
        if needsInstallSpace, freeDiskBytes < recommendedInstallBytes {
            return .warning("Runtime ready · 40 GB free is recommended while adding a game")
        }
        return .ready("Apple silicon · macOS \(operatingSystem.majorVersion) · Rosetta confirmed")
    }

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
}
