import AppKit
import Darwin
import SwiftUI

struct LocalPortsConfiguration: Codable, Equatable {
    var ports = [3000, 5173, 8080]
    var refreshInterval: TimeInterval = 30
    static let intervals: [TimeInterval] = [15, 30, 60]

    func normalized() -> Self {
        var value = self
        var seen: Set<Int> = []
        value.ports = Array(ports.filter { (1...65_535).contains($0) && seen.insert($0).inserted }.prefix(5))
        if value.ports.isEmpty { value.ports = Self().ports }
        value.refreshInterval = Self.intervals.contains(refreshInterval) ? refreshInterval : 30
        return value
    }

    static func parse(_ text: String) -> [Int]? {
        let parts = text.split { $0 == "," || $0.isWhitespace }
        let ports = parts.compactMap { Int($0) }
        guard (1...5).contains(parts.count), ports.count == parts.count,
            Set(ports).count == ports.count, ports.allSatisfy({ (1...65_535).contains($0) }) else { return nil }
        return ports
    }
}

enum LocalPortState: Equatable {
    case open, closed, unavailable(String)
    var title: String {
        switch self { case .open: "Open"; case .closed: "Closed"; case .unavailable: "Unavailable" }
    }
    var detail: String {
        switch self {
        case .open: "A TCP connection succeeded on the IPv4 or IPv6 loopback address."
        case .closed: "Both loopback addresses refused the TCP connection."
        case .unavailable(let reason): reason
        }
    }
}

struct LocalPortItem: Equatable, Identifiable {
    let port: Int
    let state: LocalPortState
    var id: Int { port }
}

protocol LocalPortReading {
    func state(port: UInt16) -> LocalPortState
}

struct LocalPortReader: LocalPortReading {
    func state(port: UInt16) -> LocalPortState {
        guard port > 0 else { return .unavailable("Invalid TCP port.") }
        let ipv4 = probe(port: port, ipv6: false)
        if ipv4 == .open { return .open }
        let ipv6 = probe(port: port, ipv6: true)
        if ipv6 == .open { return .open }
        if ipv4 == .closed, ipv6 == .closed { return .closed }
        if case .unavailable = ipv4 { return ipv4 }
        return ipv6
    }

    private func probe(port: UInt16, ipv6: Bool) -> LocalPortState {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return failure(errno) }
        defer { close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) >= 0 else { return failure(errno) }
        let result: Int32
        if ipv6 {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = port.bigEndian
            address.sin6_addr = in6addr_loopback
            result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
        } else {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
            result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        if result == 0 { return .open }
        guard errno == EINPROGRESS else { return failure(errno) }
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&descriptor, 1, 250)
        guard ready > 0 else { return ready == 0 ? .unavailable("TCP probe timed out.") : failure(errno) }
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0 else { return failure(errno) }
        return error == 0 ? .open : failure(error)
    }

    private func failure(_ code: Int32) -> LocalPortState {
        if code == ECONNREFUSED { return .closed }
        if code == EACCES || code == EPERM { return .unavailable("Permission denied while checking the local port.") }
        if code == EINTR { return .unavailable("TCP probe was interrupted.") }
        return .unavailable("TCP probe failed (system error \(code)).")
    }
}

final class LocalPortsStore: ObservableObject, PanelModuleRuntime {
    @Published private(set) var configuration: LocalPortsConfiguration
    @Published private(set) var items: [LocalPortItem] = []
    @Published private(set) var observedAt: Date?
    @Published private(set) var isRefreshing = false
    private let reader: any LocalPortReading
    private let queue = DispatchQueue(label: "DockDeck.LocalPorts", qos: .utility)
    private var cadence = ModuleRefreshCadence(backgroundMultiplier: 3)
    private var request: Progress?
    private var timer: Timer?
    private var generation = 0
    private var running = false

    init(configuration: LocalPortsConfiguration = PanelSettings.localPortsConfiguration,
        reader: any LocalPortReading = LocalPortReader(), initialItems: [LocalPortItem] = []) {
        self.configuration = configuration.normalized()
        self.reader = reader
        self.items = initialItems
        self.observedAt = initialItems.isEmpty ? nil : Date()
    }

    deinit { request?.cancel(); timer?.invalidate() }

    func start() { guard !running else { return }; running = true; schedule(); refresh() }
    func stop() { request?.cancel(); running = false; timer?.invalidate(); timer = nil; generation += 1; isRefreshing = false }
    func updateConfiguration(_ value: LocalPortsConfiguration) {
        request?.cancel()
        configuration = value.normalized()
        generation += 1
        isRefreshing = false
        items = []
        observedAt = nil
        if running { schedule(); refresh() }
    }
    func setRuntimeActivity(_ activity: ModuleRuntimeActivity, lowPowerMode: Bool) {
        if cadence.update(activity: activity, lowPowerMode: lowPowerMode), running { schedule() }
    }
    func refresh() {
        guard running, !isRefreshing else { return }
        isRefreshing = true
        let token = generation
        let ports = configuration.ports
        let reader = reader
        let progress = Progress(totalUnitCount: 1)
        request = progress
        queue.async {
            var items: [LocalPortItem] = []
            for port in ports {
                guard !progress.isCancelled else { return }
                items.append(LocalPortItem(port: port, state: reader.state(port: UInt16(port))))
            }
            let results = items
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.generation == token else { return }
                self.request = nil
                self.items = results
                self.observedAt = Date()
                self.isRefreshing = false
            }
        }
    }
    private func schedule() {
        timer?.invalidate()
        timer = .moduleRefreshTimer(interval: cadence.effectiveInterval(configuredInterval: configuration.refreshInterval)) { [weak self] in self?.refresh() }
    }
}

struct LocalPortsPanelView: View {
    @ObservedObject var store: LocalPortsStore
    let theme: Theme
    var body: some View {
        HStack(spacing: 4) {
            if store.items.isEmpty {
                Text("Checking local ports…").font(.system(size: 10))
            } else {
                ForEach(store.items) { item in
                    VStack(spacing: 4) {
                        Text(String(item.port)).monospacedDigit()
                        Text(item.state == .open ? "Open" : item.state == .closed ? "Closed" : "Error")
                            .foregroundStyle(item.state == .open ? .green : item.state == .closed ? .secondary : .orange)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).help(item.state.detail)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("TCP port \(String(item.port)), \(item.state.title)")
                    .accessibilityValue(item.state.detail)
                }
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(nsColor: theme.foregroundColor))
        .padding(.horizontal, 6).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }
}

struct LocalPortsDetailView: View {
    @ObservedObject var store: LocalPortsStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("TCP loopback · 127.0.0.1 / ::1").font(.headline)
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(String(item.port)) · \(item.state.title)").font(.headline)
                        Text(item.state.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let date = store.observedAt { Text("Checked \(date.formatted(date: .omitted, time: .standard))").font(.caption) }
                Text("Opening a TCP connection checks reachability only. It does not verify application health. No payload is sent and no processes are stopped.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
    }
}

struct LocalPortsSettingsView: View {
    @ObservedObject var model: SettingsPanelModel
    @State private var ports = ""
    @State private var error: String?
    var body: some View {
        Form {
            TextField("TCP ports (up to 5)", text: $ports)
            Button("Apply Ports") {
                guard let parsed = LocalPortsConfiguration.parse(ports) else {
                    error = "Enter 1–5 unique ports between 1 and 65535, separated by commas."
                    return
                }
                var value = model.values.localPorts
                value.ports = parsed
                model.setLocalPortsConfiguration(value)
                error = nil
            }
            if let error { Text(error).foregroundStyle(.red) }
            Picker("Refresh", selection: Binding(get: { model.values.localPorts.refreshInterval }, set: { interval in
                var value = model.values.localPorts
                value.refreshInterval = interval
                model.setLocalPortsConfiguration(value)
            })) {
                ForEach(LocalPortsConfiguration.intervals, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
            }
            Text("Checks only IPv4 and IPv6 loopback TCP ports. Hidden panels poll less often. Process ownership is not collected; no elevated access is needed.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).onAppear { ports = model.values.localPorts.ports.map(String.init).joined(separator: ", ") }
    }
}
