import Foundation

struct AppConfig: Codable {
    var bezelGaps: [Double] = [0, 0]
    var audioDelay: Double = 0
    var frameDelay: Double = 0
    var audioLanguages: [String] = []
    var subtitleLanguages: [String] = ["en"]
    var subtitlePosition: String = "bottom"
    var volumeBoost: Double = 0.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bezelGaps = try c.decodeIfPresent([Double].self, forKey: .bezelGaps) ?? [0, 0]
        audioDelay = try c.decodeIfPresent(Double.self, forKey: .audioDelay) ?? 0
        frameDelay = try c.decodeIfPresent(Double.self, forKey: .frameDelay) ?? 0
        audioLanguages = try c.decodeIfPresent([String].self, forKey: .audioLanguages) ?? []
        subtitleLanguages = try c.decodeIfPresent([String].self, forKey: .subtitleLanguages) ?? ["en"]
        subtitlePosition = try c.decodeIfPresent(String.self, forKey: .subtitlePosition) ?? "bottom"
        volumeBoost = try c.decodeIfPresent(Double.self, forKey: .volumeBoost) ?? 0.0
    }
}

enum Config {
    private static let configDir = "\(NSHomeDirectory())/.config/polyptych"
    static let configPath = "\(NSHomeDirectory())/.config/polyptych/config.json"

    @inline(never)
    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    static func save(_ config: AppConfig) {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(config)
        try? data?.write(to: URL(fileURLWithPath: configPath))
    }

    /// Read volumeBoost directly from the config file. Every call re-reads from disk.
    static func readVolumeBoost() -> Double {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let val = json["volumeBoost"] as? Double
        else {
            try? "readVolumeBoost: FAILED (config missing or invalid)\n".write(toFile: "/tmp/polyptych-filter.log", atomically: true, encoding: .utf8)
            return 0.0
        }
        try? "readVolumeBoost: \(val)\n".write(toFile: "/tmp/polyptych-filter.log", atomically: true, encoding: .utf8)
        return val
    }
}
