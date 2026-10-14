import Foundation

@MainActor enum AppEnvironment { static let isDemo = false }
@MainActor final class ProviderVisibilityStore {
    static let shared = ProviderVisibilityStore()
    let selected: [IslandProvider] = [.codex]
}
@MainActor final class UsageStore {
    static let shared = UsageStore()
    let claude = AppUsage.empty
    let codex = AppUsage(fiveHour: WindowUsage(usedPercent: 0.3, resetAt: nil, error: nil),
                         weekly: .unknown, reportedWindows: [.fiveHour])
}
@MainActor final class ProviderConnectionStore {
    static let shared = ProviderConnectionStore()
    func snapshot(_ provider: IslandProvider) -> ConnectedUsage { ConnectedUsage() }
}

@main enum MetricsExporterTests {
    @MainActor static func main() async throws {
        let suite = "MetricsExporterTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let exporter = MetricsExporter(defaults: defaults)
        precondition(!exporter.enabled && exporter.port == 9464)
        exporter.startIfEnabled()
        precondition(!exporter.listening)
        exporter.setPort(0)
        precondition(exporter.port == 9464)
        exporter.setPort(29464)
        exporter.enabled = true
        try await waitForListener(exporter)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: URL(string: "http://127.0.0.1:29464/metrics")!)
        precondition((response as? HTTPURLResponse)?.statusCode == 200)
        precondition(String(decoding: data, as: UTF8.self).contains("} 0.3"))
        exporter.setPort(29465)
        try await waitForListener(exporter)
        let (_, moved) = try await session.data(from: URL(string: "http://127.0.0.1:29465/metrics")!)
        precondition((moved as? HTTPURLResponse)?.statusCode == 200)
        let restored = MetricsExporter(defaults: defaults)
        precondition(restored.enabled && restored.port == 29465)
        exporter.enabled = false
        precondition(!exporter.listening)
        try await Task.sleep(nanoseconds: 100_000_000)
        do {
            _ = try await session.data(from: URL(string: "http://127.0.0.1:29465/metrics")!)
            fatalError("Disabled exporter still accepting connections")
        } catch {}
        precondition(!MetricsExporter(defaults: defaults).enabled)
        print("MetricsExporterTests passed")
    }

    @MainActor private static func waitForListener(_ exporter: MetricsExporter) async throws {
        for _ in 0..<30 {
            if exporter.listening { return }
            if let error = exporter.errorMessage { fatalError(error) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        fatalError("Listener did not start")
    }
}
