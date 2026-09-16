import CoreBluetooth
import Foundation

struct BluetoothKeyboardInfo: Equatable, Sendable {
  let name: String
  let isConnected: Bool
  let batteryPercent: Int?
  let address: String?
}

enum BluetoothKeyboardInfoReader {
  static func fetch() async -> BluetoothKeyboardInfo? {
    guard let info = await Task.detached(priority: .utility, operation: {
      fetchSynchronously()
    }).value else {
      return nil
    }

    guard info.isConnected, info.batteryPercent == nil else { return info }
    guard let batteryPercent = await BluetoothBatteryLevelReader.fetch(
      matchingName: info.name
    ) else {
      return info
    }

    return BluetoothKeyboardInfo(
      name: info.name,
      isConnected: info.isConnected,
      batteryPercent: batteryPercent,
      address: info.address
    )
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

final class BluetoothBatteryLevelReader: NSObject,
  CBCentralManagerDelegate,
  CBPeripheralDelegate
{
  private static let batteryService = CBUUID(string: "180F")
  private static let batteryLevelCharacteristic = CBUUID(string: "2A19")

  private let targetName: String
  private let queue = DispatchQueue(
    label: "com.olivia.CodexLinxDisplay.bluetooth-battery",
    qos: .utility
  )
  private var centralManager: CBCentralManager?
  private var peripheral: CBPeripheral?
  private var completion: ((Int?) -> Void)?

  private init(targetName: String) {
    self.targetName = targetName
  }

  static func fetch(
    matchingName name: String,
    timeout: TimeInterval = 5
  ) async -> Int? {
    await withCheckedContinuation { continuation in
      let reader = BluetoothBatteryLevelReader(targetName: name)
      reader.start(timeout: timeout) { batteryPercent in
        continuation.resume(returning: batteryPercent)
      }
    }
  }

  static func parseBatteryLevel(_ data: Data?) -> Int? {
    guard let rawValue = data?.first, rawValue <= 100 else { return nil }
    return Int(rawValue)
  }

  private func start(
    timeout: TimeInterval,
    completion: @escaping (Int?) -> Void
  ) {
    self.completion = completion
    centralManager = CBCentralManager(delegate: self, queue: queue)
    queue.asyncAfter(deadline: .now() + timeout) { [self] in
      finish(with: nil)
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central.state == .poweredOn else {
      if central.state != .unknown, central.state != .resetting {
        finish(with: nil)
      }
      return
    }

    let connected = central.retrieveConnectedPeripherals(
      withServices: [Self.batteryService]
    )
    if let matchingPeripheral = connected.first(where: matchesTarget) {
      inspect(matchingPeripheral, using: central)
      return
    }

    central.scanForPeripherals(
      withServices: [Self.batteryService],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    guard matchesTarget(peripheral) else { return }
    central.stopScan()
    inspect(peripheral, using: central)
  }

  func centralManager(
    _ central: CBCentralManager,
    didConnect peripheral: CBPeripheral
  ) {
    discoverBatteryService(on: peripheral)
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    finish(with: nil)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil,
          let service = peripheral.services?.first(where: {
            $0.uuid == Self.batteryService
          })
    else {
      finish(with: nil)
      return
    }
    peripheral.discoverCharacteristics(
      [Self.batteryLevelCharacteristic],
      for: service
    )
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard error == nil,
          let characteristic = service.characteristics?.first(where: {
            $0.uuid == Self.batteryLevelCharacteristic
          })
    else {
      finish(with: nil)
      return
    }
    peripheral.readValue(for: characteristic)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard error == nil else {
      finish(with: nil)
      return
    }
    finish(with: Self.parseBatteryLevel(characteristic.value))
  }

  private func inspect(_ peripheral: CBPeripheral, using central: CBCentralManager) {
    self.peripheral = peripheral
    peripheral.delegate = self
    if peripheral.state == .connected {
      discoverBatteryService(on: peripheral)
    } else {
      central.connect(peripheral)
    }
  }

  private func discoverBatteryService(on peripheral: CBPeripheral) {
    peripheral.discoverServices([Self.batteryService])
  }

  private func matchesTarget(_ peripheral: CBPeripheral) -> Bool {
    guard let name = peripheral.name else { return false }
    return Self.normalized(name) == Self.normalized(targetName)
  }

  private static func normalized(_ value: String) -> String {
    String(value.lowercased().filter { $0.isLetter || $0.isNumber })
  }

  private func finish(with batteryPercent: Int?) {
    guard let completion else { return }
    self.completion = nil
    centralManager?.stopScan()
    completion(batteryPercent)
  }
}
