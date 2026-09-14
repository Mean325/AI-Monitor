import XCTest

@testable import CodexLinxDisplay

final class BluetoothKeyboardInfoTests: XCTestCase {
  func testParsesConnectedLinxKeyboardDetails() throws {
    let data = try XCTUnwrap(
      """
      {
        "SPBluetoothDataType": [{
          "device_connected": [{
            "Linx68 BT-1": {
              "device_address": "CC:3D:60:35:E6:1E",
              "device_batteryLevelMain": "87%",
              "device_minorType": "Keyboard"
            }
          }]
        }]
      }
      """.data(using: .utf8)
    )

    XCTAssertEqual(
      BluetoothKeyboardInfoReader.parse(data),
      BluetoothKeyboardInfo(
        name: "Linx68 BT-1",
        isConnected: true,
        batteryPercent: 87,
        address: "CC:3D:60:35:E6:1E"
      )
    )
  }

  func testParsesPairedButDisconnectedLinxKeyboard() throws {
    let data = try XCTUnwrap(
      """
      {
        "SPBluetoothDataType": [{
          "device_not_connected": [{
            "LINX 68": { "device_address": "AA:BB:CC:DD:EE:FF" }
          }]
        }]
      }
      """.data(using: .utf8)
    )

    XCTAssertEqual(
      BluetoothKeyboardInfoReader.parse(data),
      BluetoothKeyboardInfo(
        name: "LINX 68",
        isConnected: false,
        batteryPercent: nil,
        address: "AA:BB:CC:DD:EE:FF"
      )
    )
  }
}
