import Foundation

public enum IndexDecodingError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "This catalog uses format version \(version), which needs a newer SkillsHub."
        }
    }
}

public enum IndexDecoding {
    private struct Header: Decodable {
        let schemaVersion: Int
    }

    /// Decodes a catalog, refusing one whose schema is newer than this build understands.
    /// The header is only read when the full decode fails, so a good catalog is parsed once.
    public static func decode(_ data: Data) throws -> CatalogIndex {
        let decoder = makeDecoder()
        let index: CatalogIndex
        do {
            index = try decoder.decode(CatalogIndex.self, from: data)
        } catch {
            if let header = try? decoder.decode(Header.self, from: data),
               header.schemaVersion > CatalogIndex.supportedSchemaVersion {
                throw IndexDecodingError.unsupportedSchema(header.schemaVersion)
            }
            throw error
        }
        guard index.schemaVersion <= CatalogIndex.supportedSchemaVersion else {
            throw IndexDecodingError.unsupportedSchema(index.schemaVersion)
        }
        return index
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
