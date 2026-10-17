import Foundation

// Folia/Features/TuningManifest.swift — generated defaults and portable, bounded JSON tuning values.
indirect enum TuningValue: Codable, Equatable, Sendable {
    case bool(Bool), number(Double), string(String), object([String: TuningValue]), array([TuningValue]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let object = try? value.decode([String: TuningValue].self) { self = .object(object) }
        else { self = .array(try value.decode([TuningValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .bool(let bool): try value.encode(bool)
        case .number(let number): try value.encode(number)
        case .string(let string): try value.encode(string)
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .null: try value.encodeNil()
        }
    }
}

struct TuningManifest {
    static var defaults: [String: [String: TuningValue]] {
        guard let url = Bundle.main.url(forResource: "tuning-defaults", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count < 1_000_000,
              let values = try? JSONDecoder().decode([String: [String: TuningValue]].self, from: data),
              (try? validate(values)) != nil else { return [:] }
        return values
    }
    static func validate(_ values: [String: [String: TuningValue]]) throws {
        guard values.count <= 32 else { throw CocoaError(.fileReadCorruptFile) }
        var count = 0
        for (mode, fields) in values {
            guard mode.count <= 100 else { throw CocoaError(.fileReadCorruptFile) }
            try validate(.object(fields), depth: 0, count: &count)
        }
    }
    private static func validate(_ value: TuningValue, depth: Int, count: inout Int) throws {
        count += 1
        guard depth <= 6, count <= 2000 else { throw CocoaError(.fileReadCorruptFile) }
        switch value {
        case .number(let number): guard number.isFinite, abs(number) <= 100_000 else { throw CocoaError(.fileReadCorruptFile) }
        case .string(let string): guard string.count <= 1024 else { throw CocoaError(.fileReadCorruptFile) }
        case .object(let object):
            guard object.count <= 256, object.keys.allSatisfy({ $0.count <= 100 }) else { throw CocoaError(.fileReadCorruptFile) }
            for child in object.values { try validate(child, depth: depth + 1, count: &count) }
        case .array(let array):
            guard array.count <= 256 else { throw CocoaError(.fileReadCorruptFile) }
            for child in array { try validate(child, depth: depth + 1, count: &count) }
        default: break
        }
    }
    // Nested defaults are exposed as stable field paths while their JSON hierarchy stays intact.
    static func leaves(_ fields: [String: TuningValue], prefix: [String] = []) -> [(path: [String], value: TuningValue)] {
        fields.keys.sorted().flatMap { key -> [(path: [String], value: TuningValue)] in
            let path = prefix + [key]
            guard let value = fields[key] else { return [] }
            if case .object(let children) = value { return leaves(children, prefix: path) }
            return [(path, value)]
        }
    }
    static func replacing(_ fields: [String: TuningValue], path: [String], with value: TuningValue) -> [String: TuningValue] {
        guard let first = path.first else { return fields }
        var result = fields
        if path.count == 1 { result[first] = value }
        else if let existing = fields[first], case .object(let children) = existing {
            result[first] = .object(replacing(children, path: Array(path.dropFirst()), with: value))
        }
        return result
    }
}

