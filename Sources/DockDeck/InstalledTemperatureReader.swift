import Darwin
import Foundation
import Security

enum SMCTemperatureOutputParser {
    static func hottestCPUCelsius(from output: String, chipGeneration: Int?) -> Double? {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2 else { return nil }
            let key = fields[0]
            guard key.count == 6, key.first == "[", key.last == "]",
                let value = Double(fields[1]),
                value.isFinite,
                (5...125).contains(value),
                isCPUSensor(String(key.dropFirst().dropLast()), chipGeneration: chipGeneration)
            else { return nil }
            return value
        }
        .max()
    }

    private static func isCPUSensor(_ key: String, chipGeneration: Int?) -> Bool {
        switch chipGeneration {
        case 1, 2: key.hasPrefix("Tp")
        case 3: key.hasPrefix("Te") || key.hasPrefix("Tf0") || key.hasPrefix("Tf4")
        case 4: key.hasPrefix("Te") || key.hasPrefix("Tp")
        case 5: key.hasPrefix("Tp")
        default: key.hasPrefix("TC")
        }
    }
}

enum InstalledTemperatureReader {
    private static let statsRequirement =
        #"identifier "eu.exelban.Stats" and anchor apple generic and certificate leaf[subject.OU] = "RP2S87B72W""#
    private static let statsToolURL = validatedStatsToolURL()

    static var isAvailable: Bool { statsToolURL != nil }

    static func readHottestCPUCelsius() -> Double? {
        guard let executableURL = statsToolURL else { return nil }

        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["list", "-t"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 2, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()

        guard process.terminationStatus == 0, data.count <= 256 * 1_024,
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return SMCTemperatureOutputParser.hottestCPUCelsius(
            from: text, chipGeneration: appleChipGeneration())
    }

    private static func appleChipGeneration() -> Int? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
            size > 1
        else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &value, &size, nil, 0) == 0 else {
            return nil
        }
        let brand = String(cString: value)
        guard let marker = brand.range(of: "Apple M") else { return nil }
        let digits = brand[marker.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private static func validatedStatsToolURL() -> URL? {
        let appURL = URL(fileURLWithPath: "/Applications/Stats.app", isDirectory: true)
        let toolURL = appURL.appendingPathComponent("Contents/Resources/smc")
        guard FileManager.default.isExecutableFile(atPath: toolURL.path) else { return nil }

        var code: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess,
            let code
        else { return nil }

        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(
                statsRequirement as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return nil }

        let flags = SecCSFlags(
            rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSStrictValidate))
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
        else { return nil }

        // ponytail: This read-only adapter avoids bundling private SMC code. Replace it with a
        // separately reviewed native sensor helper if DockDeck later ships numeric sensors itself.
        return toolURL
    }
}
