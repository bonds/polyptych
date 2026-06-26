import Foundation

struct LoudnessMeasurement: Codable {
    let input_i: Double
    let input_lra: Double
    let input_tp: Double
    let input_thresh: Double

    enum CodingKeys: String, CodingKey {
        case input_i, input_lra, input_tp, input_thresh
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input_i = try Self.decodeDouble(c, forKey: .input_i)
        input_lra = try Self.decodeDouble(c, forKey: .input_lra)
        input_tp = try Self.decodeDouble(c, forKey: .input_tp)
        input_thresh = try Self.decodeDouble(c, forKey: .input_thresh)
    }

    private static func decodeDouble(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Double {
        if let num = try? c.decodeIfPresent(Double.self, forKey: key) {
            return num
        }
        let str = try c.decode(String.self, forKey: key)
        guard let val = Double(str) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Expected Double or String, got '\(str)'")
        }
        return val
    }
}
