import Foundation

/// Real, sustained workloads a button can trigger. Unlike crash/hang/memory
/// exception (instant, one-shot), `cpuException`/`diskWriteException` only
/// fire after crossing an undocumented Apple threshold over some sustained
/// period - and `cpuTime`/`cpuInstructionsCount` are continuous daily
/// aggregates with no discrete trigger at all. The most a button can do for
/// any of these is contribute real work toward them, then wait for the next
/// report (or, for the exceptions, hope the threshold was crossed).
enum Workloads {
  /// 4 concurrent busy-loops for `duration` - feeds `cpuException` if
  /// MetricKit's threshold happens to be crossed (not guaranteed), and
  /// unconditionally contributes to `cpuTime`/`cpuInstructionsCount`.
  /// `sin`/`sqrt` accumulation plus a live deadline check keeps this from
  /// being optimized away as dead code.
  static func runCPUBusyWorkload(duration: TimeInterval = 60, completion: @escaping () -> Void) {
    let group = DispatchGroup()
    for _ in 0..<4 {
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        let deadline = Date().addingTimeInterval(duration)
        var x = 1.0
        while Date() < deadline {
          x = sin(x) + sqrt(abs(x) + 1)
        }
        group.leave()
      }
    }
    group.notify(queue: .main, execute: completion)
  }

  /// Sustained writes to a scratch file under Caches (never Documents - no
  /// iCloud backup, no user-visible pollution), cleaned up regardless of
  /// success/cancellation so repeated taps can't fill the device disk. Feeds
  /// `diskWriteException` if MetricKit's threshold happens to be crossed
  /// (not guaranteed, undocumented).
  static func runDiskWriteWorkload(
    duration: TimeInterval = 60, totalBytes: Int = 1_000_000_000,
    completion: @escaping () -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let scratchURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("hitchscope-disk-workload.tmp")
      defer { try? FileManager.default.removeItem(at: scratchURL) }

      FileManager.default.createFile(atPath: scratchURL.path, contents: nil)
      guard let handle = try? FileHandle(forWritingTo: scratchURL) else {
        DispatchQueue.main.async(execute: completion)
        return
      }
      defer { try? handle.close() }

      let chunk = Data(repeating: 0xFF, count: 1_000_000)
      let deadline = Date().addingTimeInterval(duration)
      var written = 0
      while Date() < deadline && written < totalBytes {
        try? handle.write(contentsOf: chunk)
        written += chunk.count
      }
      DispatchQueue.main.async(execute: completion)
    }
  }

  /// A *bounded* single allocation spike (unlike the unbounded memory-
  /// exception trigger's loop) - held briefly then released, so it can set
  /// the day's `peakMemory` without crossing into jetsam territory.
  static func runPeakMemorySpike(
    megabytes: Int = 300, holdDuration: TimeInterval = 2, completion: @escaping () -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      var blocks: [[UInt8]] = []
      let blockCount = max(1, megabytes / 50)
      for _ in 0..<blockCount {
        blocks.append([UInt8](repeating: 0xFF, count: 50_000_000))
      }
      Thread.sleep(forTimeInterval: holdDuration)
      blocks.removeAll()
      DispatchQueue.main.async(execute: completion)
    }
  }

  /// A real network round-trip (~5MB GET, ~2MB POST) against a public dummy-
  /// data testing endpoint - no real user data leaves the device. Which of
  /// the 4 WiFi/cellular upload/download kinds this contributes to is
  /// decided by the device's actual connectivity at the time, not the app.
  static func runNetworkWorkload(completion: @escaping @MainActor @Sendable () -> Void) {
    Task.detached {
      if let url = URL(string: "https://httpbin.org/bytes/5000000") {
        _ = try? await URLSession.shared.data(from: url)
      }
      if let url = URL(string: "https://httpbin.org/post") {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data((0..<2_000_000).map { _ in UInt8.random(in: 0...255) })
        _ = try? await URLSession.shared.data(for: request)
      }
      await MainActor.run(body: completion)
    }
  }
}
