import Foundation
import Network

@MainActor
final class MetricsExporter {
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    func startIfEnabled() {
        guard !AppEnvironment.isDemo,
              let raw = ProcessInfo.processInfo.environment["CODEXISLAND_METRICS_PORT"] else { return }
        guard let port = UInt16(raw), port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            NSLog("Metrics exporter: CODEXISLAND_METRICS_PORT must be between 1 and 65535")
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("Metrics exporter failed: %@", error.localizedDescription)
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            NSLog("Metrics exporter failed: %@", error.localizedDescription)
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 32 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.close(id)
        }
        receive(connection, id: id, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                guard buffer.count <= 8192, error == nil else { self.close(id); return }
                if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                    let request = String(decoding: buffer, as: UTF8.self)
                    let first = request.components(separatedBy: "\r\n")[0].split(separator: " ")
                    let ok = first.count == 3 && first[0] == "GET" && first[1] == "/metrics"
                    let body = ok ? self.snapshot() : "Not found\n"
                    let status = ok ? "200 OK" : "404 Not Found"
                    let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; version=0.0.4; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
                        Task { @MainActor in self?.close(id) }
                    })
                } else if complete {
                    self.close(id)
                } else {
                    self.receive(connection, id: id, buffer: buffer)
                }
            }
        }
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
    }

    private func snapshot() -> String {
        var readings: [QuotaMetric] = []
        for provider in ProviderVisibilityStore.shared.selected {
            if provider.usesLegacyUsage {
                let usage = provider == .claude ? UsageStore.shared.claude : UsageStore.shared.codex
                for kind in usage.visibleWindows {
                    let window = usage.window(kind)
                    readings.append(QuotaMetric(provider: provider.rawValue, window: kind.rawValue,
                        group: "default", usedFraction: window.hasPercentageReading ? window.usedPercent : nil,
                        resetAt: window.resetAt, fresh: window.error == nil))
                }
            } else {
                let usage = ProviderConnectionStore.shared.snapshot(provider)
                for limit in usage.limits {
                    readings.append(QuotaMetric(provider: provider.rawValue, window: limit.id,
                        group: limit.groupID, usedFraction: limit.usedFraction,
                        resetAt: limit.resetAt, fresh: !usage.refreshFailed && !usage.needsLogin && usage.updatedAt != nil))
                }
            }
        }
        return UsageMetrics.render(readings)
    }
}
