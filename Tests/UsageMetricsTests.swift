import Foundation

@main
enum UsageMetricsTests {
    static func main() {
        let rows = [
            QuotaMetric(provider: "codex", window: "weekly", group: "default", usedFraction: 0, resetAt: Date(timeIntervalSince1970: 123), fresh: true),
            QuotaMetric(provider: "claude", window: "fiveHour", group: "default", usedFraction: 0.4, resetAt: nil, fresh: false),
            QuotaMetric(provider: "muse", window: "session", group: "default", usedFraction: 1.2, resetAt: nil, fresh: true),
            QuotaMetric(provider: "grok", window: "unknown", group: "default", usedFraction: nil, resetAt: nil, fresh: true),
            QuotaMetric(provider: "test", window: "bad", group: "a\"b\\c\nd", usedFraction: .nan, resetAt: nil, fresh: true)
        ]
        let output = UsageMetrics.render(rows)
        precondition(output.contains("codexisland_quota_used_ratio{provider=\"codex\",window=\"weekly\",group=\"default\"} 0.0"))
        precondition(output.contains("codexisland_quota_reset_timestamp_seconds{provider=\"codex\",window=\"weekly\",group=\"default\"} 123.0"))
        precondition(!output.contains("quota_used_ratio{provider=\"claude\""))
        precondition(!output.contains("quota_used_ratio{provider=\"grok\""))
        precondition(!output.contains("quota_used_ratio{provider=\"test\""))
        precondition(output.contains("codexisland_quota_remaining_ratio{provider=\"muse\",window=\"session\",group=\"default\"} 0.0"))
        precondition(output.contains("group=\"a\\\"b\\\\c\\nd\""))
        precondition(output.hasSuffix("\n"))
        print("UsageMetricsTests passed")
    }
}
