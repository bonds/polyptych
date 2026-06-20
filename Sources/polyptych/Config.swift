import Foundation

struct AppConfig: Codable {
    var bezelGaps: [Double] = [0, 0]
    var audioDelay: Double = 0
    var frameDelay: Double = 0
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
