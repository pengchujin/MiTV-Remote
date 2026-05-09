import AppKit

final class BrightnessController {
    private let miTV = MiTVController()

    private enum Tool {
        case m1ddc(URL)
        case ddcctl(URL)
    }

    func brightnessStatus() async -> Result<Int, CECResult> {
        guard let tool = findTool() else { return .success(50) }
        switch tool {
        case .m1ddc(let url):
            let result = await run(url, ["get", "luminance"])
            guard result.isSuccess else { return .failure(result) }
            guard let value = parsePercent(from: result.message, keywords: ["luminance", "brightness"]) else {
                return .failure(CECResult(isSuccess: false, message: L.string("brightness.m1ddc_read_failed", result.message)))
            }
            return .success(value)
        case .ddcctl(let url):
            let result = await run(url, ["-d", "1"])
            guard result.isSuccess else { return .failure(result) }
            guard let value = parsePercent(from: result.message, keywords: ["brightness", "luminance"]) else {
                return .failure(CECResult(isSuccess: false, message: L.string("brightness.ddcctl_read_failed", result.message)))
            }
            return .success(value)
        }
    }

    func adjustBrightness(_ direction: BrightnessDirection) async -> CECResult {
        await miTV.adjustBacklight(direction)
    }

    private func findTool() -> Tool? {
        if let url = findExecutable(named: "m1ddc") { return .m1ddc(url) }
        if let url = findExecutable(named: "ddcctl") { return .ddcctl(url) }
        return nil
    }

    private func findExecutable(named name: String) -> URL? {
        let fm = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let searchPaths = pathValue.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for dir in searchPaths {
            let path = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    private func run(_ executableURL: URL, _ arguments: [String]) async -> CECResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: CECResult(isSuccess: true, message: output))
                    } else {
                        continuation.resume(returning: CECResult(isSuccess: false, message: L.string("cec.exec_failed", executableURL.lastPathComponent, output)))
                    }
                } catch {
                    continuation.resume(returning: CECResult(isSuccess: false, message: L.string("cec.cannot_start", executableURL.lastPathComponent, error.localizedDescription)))
                }
            }
        }
    }

    private func parsePercent(from output: String, keywords: [String]) -> Int? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let candidateLines = lines.filter { line in keywords.contains { line.localizedCaseInsensitiveContains($0) } } + lines
        for line in candidateLines {
            let numbers = line.split { !$0.isNumber }.compactMap { Int($0) }
            if let value = numbers.first(where: { (0...100).contains($0) }) { return value }
        }
        return nil
    }
}
