import Foundation

struct QuotaMetric {
    let provider: String
    let window: String
    let group: String
    let usedFraction: Double?
    let resetAt: Date?
    let fresh: Bool
}

enum UsageMetrics {
    static func render(_ readings: [QuotaMetric]) -> String {
        var lines = [
            "# HELP codexisland_quota_available Whether a fresh quota measurement is available (1 or 0).",
            "# TYPE codexisland_quota_available gauge",
            "# HELP codexisland_quota_used_ratio Fraction of subscription quota consumed; may exceed 1.",
            "# TYPE codexisland_quota_used_ratio gauge",
            "# HELP codexisland_quota_remaining_ratio Fraction of subscription quota remaining.",
            "# TYPE codexisland_quota_remaining_ratio gauge",
            "# HELP codexisland_quota_reset_timestamp_seconds Provider-reported reset time in Unix seconds.",
            "# TYPE codexisland_quota_reset_timestamp_seconds gauge"
        ]
        for reading in readings {
            let labels = "provider=\"\(escape(reading.provider))\",window=\"\(escape(reading.window))\",group=\"\(escape(reading.group))\""
            let valid = reading.fresh && reading.usedFraction.map { $0.isFinite && $0 >= 0 } == true
            lines.append("codexisland_quota_available{\(labels)} \(valid ? 1 : 0)")
            guard valid, let used = reading.usedFraction else { continue }
            lines.append("codexisland_quota_used_ratio{\(labels)} \(used)")
            lines.append("codexisland_quota_remaining_ratio{\(labels)} \(max(0, 1 - used))")
            if let reset = reading.resetAt?.timeIntervalSince1970, reset.isFinite {
                lines.append("codexisland_quota_reset_timestamp_seconds{\(labels)} \(reset)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
