import Foundation

/// Bezel gaps between adjacent screens, as fraction of screen width.
/// gaps[i] = bezel between screen[i] and screen[i+1].
struct BezelCalibration: Codable {
    var gaps: [Double] = [0.075, 0.075]
}

struct AppConfig: Codable {
    var bezel: BezelCalibration = BezelCalibration()
}

enum Config {
    private static let configDir = "\(NSHomeDirectory())/.config/polyptych"
    private static let configPath = "\(configDir)/config.json"

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
}
