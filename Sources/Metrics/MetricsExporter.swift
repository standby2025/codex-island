import Foundation
import Network
import Combine

@MainActor
final class MetricsExporter: ObservableObject {
    static let shared = MetricsExporter()
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "MacIsland.metricsEnabled")
            configure()
        }
    }
    @Published private(set) var address: String
    @Published private(set) var port: Int
    @Published private(set) var errorMessage: String?
    @Published private(set) var listening = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedAddress = defaults.string(forKey: "MacIsland.metricsAddress") ?? "0.0.0.0"
        address = Self.validAddress(storedAddress) ? storedAddress : "0.0.0.0"
        enabled = defaults.bool(forKey: "MacIsland.metricsEnabled")
        let stored = defaults.integer(forKey: "MacIsland.metricsPort")
        port = (1...65535).contains(stored) ? stored : 9464
    }

    static func validAddress(_ value: String) -> Bool {
        IPv4Address(value) != nil || IPv6Address(value) != nil
    }

    func setAddress(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validAddress(value), value != address else { return }
        address = value
        defaults.set(address, forKey: "MacIsland.metricsAddress")
        configure()
    }

    var endpointURL: String {
        let host = address.contains(":") ? "[\(address)]" : address
        return "http://\(host):\(port)/metrics"
    }

    func setPort(_ value: Int) {
        guard (1...65535).contains(value), value != port else { return }
        port = value
        defaults.set(port, forKey: "MacIsland.metricsPort")
        configure()
    }

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    func startIfEnabled() { configure() }

    private func configure() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        listening = false
        errorMessage = nil
        guard enabled, !AppEnvironment.isDemo,
              let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: endpointPort)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                Task { @MainActor in
                    guard let self, let listener, self.listener === listener else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready: self.listening = true
                    case .failed(let error):
                        self.listening = false
                        self.errorMessage = error.localizedDescription
                        listener.cancel()
                    default: break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            errorMessage = error.localizedDescription
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
