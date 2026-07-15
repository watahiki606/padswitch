import Foundation
import IOBluetooth

public struct BTDevice: Sendable, Identifiable, Equatable {
    public let name: String
    public let address: String
    public let isConnected: Bool
    public let isTrackpad: Bool

    public var id: String { address }
}

/// IOBluetooth の薄いラッパー。ペアリング済みデバイスの列挙と接続/切断を行う。
/// (切り替えの前提: トラックパッドは事前に各 Mac へ USB-C ケーブル接続でペアリング済みであること)
public enum BluetoothController {
    /// ペアリング済みデバイス一覧。トラックパッドを先頭にソートする。
    public static func pairedDevices() -> [BTDevice] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return devices.compactMap { device -> BTDevice? in
            guard let address = device.addressString else { return nil }
            let name = device.name ?? "(名称不明)"
            return BTDevice(
                name: name,
                address: address,
                isConnected: device.isConnected(),
                isTrackpad: looksLikeTrackpad(device)
            )
        }
        .sorted { ($0.isTrackpad ? 0 : 1, $0.name) < ($1.isTrackpad ? 0 : 1, $1.name) }
    }

    static func looksLikeTrackpad(_ device: IOBluetoothDevice) -> Bool {
        if let name = device.name, name.localizedCaseInsensitiveContains("trackpad") {
            return true
        }
        // Class of Device: major = Peripheral(0x05), minor の上位2bit が 10 = pointing device
        let major = device.deviceClassMajor
        let minor = device.deviceClassMinor
        return major == kBluetoothDeviceClassMajorPeripheral && (minor & 0b11_0000) == 0b10_0000
    }

    static func device(for address: String) throws -> IOBluetoothDevice {
        guard let device = IOBluetoothDevice(addressString: address) else {
            throw PadError.commandFailed("Bluetoothアドレスが不正です: \(address)")
        }
        return device
    }

    public static func isConnected(_ address: String) throws -> Bool {
        try device(for: address).isConnected()
    }

    /// 接続を試み、実際に接続状態になるまで待つ。
    public static func connect(_ address: String, timeout: TimeInterval = 10) throws {
        let device = try device(for: address)
        if device.isConnected() { return }
        let deadline = Date().addingTimeInterval(timeout)
        var lastStatus: IOReturn = kIOReturnSuccess
        repeat {
            lastStatus = device.openConnection()
            if device.isConnected() { return }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        throw PadError.timeout("トラックパッドに接続できませんでした (IOReturn: \(String(format: "0x%08x", lastStatus)))")
    }

    /// 切断し、実際に切断状態になるまで待つ。未接続なら何もしない。
    public static func disconnect(_ address: String, timeout: TimeInterval = 5) throws {
        let device = try device(for: address)
        if !device.isConnected() { return }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            device.closeConnection()
            if !device.isConnected() { return }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        throw PadError.timeout("トラックパッドを切断できませんでした")
    }
}
