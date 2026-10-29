import Foundation

/// One SHA-1 over a folder's file paths and hashes, as SkillsFlow computes `files_digest`: for
/// each file sorted by the UTF-8 bytes of its path, `<path>\0<sha>\n`. Comparing it with the
/// digest of a skill's installed files tells whether the catalog's version differs.
public enum FilesDigest {
    public static func of(_ files: [String: String]) -> String {
        var sha = SHA1()
        for path in files.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            sha.update(Data("\(path)\0\(files[path]!)\n".utf8))
        }
        return sha.hexDigest()
    }

    /// Nil when any file lacks a hash, as in catalogs from before SkillsFlow 0.2.
    public static func of(_ files: [IndexFile]) -> String? {
        var hashes: [String: String] = [:]
        for file in files {
            guard let sha = file.sha else { return nil }
            hashes[file.path] = sha
        }
        return hashes.isEmpty ? nil : of(hashes)
    }
}
