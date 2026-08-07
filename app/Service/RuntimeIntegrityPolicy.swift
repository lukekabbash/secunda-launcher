import Foundation

enum RuntimeIntegrityInspection {
    case absent
    case invalid
    case valid(manifest: URL, data: Data)
}

enum RuntimeIntegrityPolicy {
    static let relativePath = "share/secunda/runtime-files.sha256"

    static func inspect(runtimeRoot: URL) -> RuntimeIntegrityInspection {
        let manifest = runtimeRoot.appendingPathComponent(relativePath)
        let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: manifest.path)) != nil
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            return isLink ? .invalid : .absent
        }
        guard !isLink,
              contains(manifest, in: runtimeRoot),
              let data = try? Data(contentsOf: manifest),
              !data.isEmpty
        else {
            return .invalid
        }
        return .valid(manifest: manifest, data: data)
    }

    static func validatesEntries(_ data: Data, runtimeRoot: URL) -> Bool {
        guard let contents = String(data: data, encoding: .utf8) else { return false }
        let lines = contents.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }

        var targets = Set<String>()
        for rawLine in lines {
            let line = String(rawLine)
            guard line.count >= 69 else { return false }
            let hash = line.prefix(64)
            guard hash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return false }

            let suffix = line.dropFirst(64)
            guard suffix.first == " ",
                  suffix.dropFirst().first == " " || suffix.dropFirst().first == "*"
            else {
                return false
            }
            let relativePath = String(suffix.dropFirst(2))
            guard relativePath.hasPrefix("./"),
                  !relativePath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                return false
            }
            let components = relativePath.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
            else {
                return false
            }

            let target = components.reduce(runtimeRoot) { partial, component in
                partial.appendingPathComponent(String(component))
            }
            let values = try? target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard target.path != runtimeRoot.appendingPathComponent(Self.relativePath).path,
                  values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  contains(target, in: runtimeRoot)
            else {
                return false
            }
            guard targets.insert(target.resolvingSymlinksInPath().standardizedFileURL.path).inserted else {
                return false
            }
        }
        guard let runtimeFiles = regularFiles(in: runtimeRoot) else { return false }
        return targets == runtimeFiles
    }

    private static func regularFiles(in runtimeRoot: URL) -> Set<String>? {
        let manifestPath = runtimeRoot
            .appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: runtimeRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            return nil
        }

        var files = Set<String>()
        for case let candidate as URL in enumerator {
            guard contains(candidate, in: runtimeRoot),
                  let values = try? candidate.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                  )
            else {
                return nil
            }
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                continue
            }

            let path = candidate.resolvingSymlinksInPath().standardizedFileURL.path
            if path != manifestPath {
                files.insert(path)
            }
        }
        return enumerationFailed ? nil : files
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath.hasPrefix(rootPath + "/")
    }
}
