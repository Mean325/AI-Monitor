import Foundation

struct BluetoothKeyboardInfo: Equatable, Sendable {
  let name: String
  let isConnected: Bool
  let batteryPercent: Int?
  let address: String?
}

enum BluetoothKeyboardInfoReader {
  static func fetch() async -> BluetoothKeyboardInfo? {
    await Task.detached(priority: .utility) {
      fetchSynchronously()
    }.value
  }

  static func parse(_ data: Data) -> BluetoothKeyboardInfo? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let reports = root["SPBluetoothDataType"] as? [[String: Any]]
    else {
      return nil
    }

    for report in reports {
      if let device = matchingDevice(in: report["device_connected"], isConnected: true) {
        return device
      }
      if let device = matchingDevice(in: report["device_not_connected"], isConnected: false) {
        return device
      }
    }
    return nil
  }

  private static func fetchSynchronously() -> BluetoothKeyboardInfo? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPBluetoothDataType", "-json"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      let data = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      return parse(data)
    } catch {
      return nil
    }
  }

  private static func matchingDevice(
    in rawList: Any?,
    isConnected: Bool
  ) -> BluetoothKeyboardInfo? {
    guard let devices = rawList as? [[String: Any]] else { return nil }

    for device in devices {
      for (name, rawDetails) in device where normalized(name).contains("linx68") {
        let details = rawDetails as? [String: Any]
        return BluetoothKeyboardInfo(
          name: name,
          isConnected: isConnected,
          batteryPercent: batteryPercent(from: details?["device_batteryLevelMain"]),
          address: details?["device_address"] as? String
        )
      }
    }
    return nil
  }

  private static func normalized(_ value: String) -> String {
    String(value.lowercased().filter { $0.isLetter || $0.isNumber })
  }

  private static func batteryPercent(from rawValue: Any?) -> Int? {
    if let value = rawValue as? Int {
      return min(max(value, 0), 100)
    }
    guard let value = rawValue as? String else { return nil }
    let digits = value.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0.isNumber }
    guard let percent = Int(digits) else { return nil }
    return min(max(percent, 0), 100)
  }
}
