final class ModuleRuntimeCoordinator {
    private struct Runtime {
        let start: () -> Void
        let stop: () -> Void
    }

    private var runtimes: [PanelModuleID: Runtime] = [:]
    private var activeModules: Set<PanelModuleID> = []

    func register(
        _ module: PanelModuleID,
        start: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        precondition(runtimes[module] == nil, "Module runtime registered twice: \(module.rawValue)")
        runtimes[module] = Runtime(start: start, stop: stop)
    }

    func synchronize(enabledModules: [PanelModuleID]) {
        let enabledModules = Set(enabledModules).intersection(Set(runtimes.keys))

        for module in activeModules.subtracting(enabledModules) {
            runtimes[module]?.stop()
        }
        for module in enabledModules.subtracting(activeModules) {
            runtimes[module]?.start()
        }
        activeModules = enabledModules
    }

    func stopAll() {
        for module in activeModules {
            runtimes[module]?.stop()
        }
        activeModules.removeAll()
    }
}
