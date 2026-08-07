import Foundation

enum SteamGameInstallState: Equatable, Sendable {
    case missing
    case incomplete(String)
    case installed(URL)
}

struct SteamInstallProbe {
    let bottleRoot: URL
    let steamRoot: URL

    func inspect(
        appID: String,
        executableName: String,
        baselineDataFile: String? = "Data/Skyrim.esm",
        displayName: String = "Skyrim"
    ) -> SteamGameInstallState {
        guard appID.allSatisfy({ $0.isASCII && $0.isNumber }) else { return .missing }

        var sawManifest = false
        for libraryRoot in libraryRoots() {
            let manifest = libraryRoot.appendingPathComponent("steamapps/appmanifest_\(appID).acf")
            guard isContainedInBottle(manifest),
                  let contents = try? String(contentsOf: manifest, encoding: .utf8)
            else {
                continue
            }
            sawManifest = true

            guard let installDirectory = Self.firstValue(for: "installdir", in: contents),
                  let relativeInstallDirectory = Self.safeRelativePath(installDirectory),
                  Self.isCompleteManifest(contents, appID: appID)
            else {
                continue
            }

            let gameRoot = relativeInstallDirectory.reduce(
                libraryRoot.appendingPathComponent("steamapps/common", isDirectory: true)
            ) { partial, component in
                partial.appendingPathComponent(component, isDirectory: true)
            }
            let executable = gameRoot.appendingPathComponent(executableName)
            let baselineSatisfied = baselineDataFile.map {
                isContainedRegularFile(gameRoot.appendingPathComponent($0), minimumSize: 1)
            } ?? true
            if isPlausibleWindowsExecutable(executable), baselineSatisfied {
                return .installed(executable)
            }
        }

        return sawManifest
            ? .incomplete("Finish the \(displayName) download or update in Steam")
            : .missing
    }

    static func values(for key: String, in contents: String) -> [String] {
        contents.components(separatedBy: .newlines).compactMap { line in
            let fields = quotedFields(in: line)
            guard fields.count >= 2, fields[0].caseInsensitiveCompare(key) == .orderedSame else {
                return nil
            }
            return fields[1]
        }
    }

    private func libraryRoots() -> [URL] {
        var roots = isContainedInBottle(steamRoot) ? [steamRoot] : []
        let folders = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let contents = try? String(contentsOf: folders, encoding: .utf8) {
            roots.append(contentsOf: Self.values(for: "path", in: contents).compactMap(mapWindowsPath))
        }

        var seen = Set<String>()
        return roots.filter {
            seen.insert($0.resolvingSymlinksInPath().standardizedFileURL.path).inserted
        }
    }

    private func mapWindowsPath(_ path: String) -> URL? {
        let characters = Array(path)
        guard characters.count >= 3,
              characters[0].isASCII,
              characters[0].isLetter,
              characters[1] == ":",
              characters[2] == "\\" || characters[2] == "/"
        else {
            return nil
        }

        let drive = String(characters[0]).lowercased()
        let tail = String(characters.dropFirst(3))
        guard let components = Self.safeRelativePath(tail) else { return nil }

        let base = drive == "c"
            ? bottleRoot.appendingPathComponent("drive_c", isDirectory: true)
            : bottleRoot.appendingPathComponent("dosdevices/\(drive):", isDirectory: true)
        guard FileManager.default.fileExists(atPath: base.path) else { return nil }
        let library = components.reduce(base) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
        return isContainedInBottle(library) ? library : nil
    }

    private static func isCompleteManifest(_ contents: String, appID: String) -> Bool {
        guard firstValue(for: "appid", in: contents) == appID,
              firstValue(for: "StateFlags", in: contents).flatMap(Int.init) == 4
        else {
            return false
        }
        return completedBytes("BytesDownloaded", expected: "BytesToDownload", in: contents)
            && completedBytes("BytesStaged", expected: "BytesToStage", in: contents)
    }

    private static func completedBytes(
        _ completedKey: String,
        expected expectedKey: String,
        in contents: String
    ) -> Bool {
        guard let expected = firstValue(for: expectedKey, in: contents).flatMap(Int64.init),
              let completed = firstValue(for: completedKey, in: contents).flatMap(Int64.init)
        else {
            return true
        }
        return completed >= expected
    }

    private static func firstValue(for key: String, in contents: String) -> String? {
        values(for: key, in: contents).first
    }

    private static func safeRelativePath(_ path: String) -> [String]? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\") else { return nil }
        let components = path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains(":") })
        else {
            return nil
        }
        return components
    }

    private static func quotedFields(in line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in line {
            if isEscaped {
                current.append(character)
                isEscaped = false
            } else if isQuoted && character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                if isQuoted {
                    fields.append(current)
                    current = ""
                }
                isQuoted.toggle()
            } else if isQuoted {
                current.append(character)
            }
        }
        return fields
    }

    private func isContainedInBottle(_ candidate: URL) -> Bool {
        let resolvedBottle = bottleRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedCandidate.hasPrefix(resolvedBottle + "/")
    }

    private func isPlausibleWindowsExecutable(_ executable: URL) -> Bool {
        guard isContainedRegularFile(executable, minimumSize: 4_096),
              let handle = try? FileHandle(forReadingFrom: executable)
        else {
            return false
        }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data([0x4d, 0x5a])
    }

    private func isContainedRegularFile(_ file: URL, minimumSize: Int64) -> Bool {
        guard isContainedInBottle(file),
              let values = try? file.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
              ])
        else {
            return false
        }
        return values.isRegularFile == true
            && values.isSymbolicLink != true
            && Int64(values.fileSize ?? 0) >= minimumSize
    }
}
