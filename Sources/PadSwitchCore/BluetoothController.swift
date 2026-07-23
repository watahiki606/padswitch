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
    ///
    /// 待機中の Magic 系デバイスは無線でのペアリング要求を受け付けない(電源入れ直し直後の
    /// 発見可能モードか、ケーブル接続時のみ可能)。そのため接続はペアリング済みが前提で、
    /// 切り替えは接続・切断のみで行う。
    public static func connect(_ address: String, timeout: TimeInterval = 10) throws {
        let device = try device(for: address)
        if device.isConnected() { return }
        guard device.isPaired() else {
            throw PadError.commandFailed(
                "トラックパッドがこのMacとペアリングされていません。トラックパッドの電源を入れ直してからペアリングするか、USB-Cケーブルで一度接続してください"
            )
        }
        if tryOpenConnection(device, within: timeout) { return }
        throw PadError.timeout("トラックパッドに接続できませんでした。電源と距離を確認してください")
    }

    static func tryOpenConnection(_ device: IOBluetoothDevice, within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            _ = device.openConnection()
            if device.isConnected() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return false
    }

    /// ペアリングを実行する。Magic 系 HID デバイスは Just Works 方式のため PIN 入力は不要。
    /// 相手が発見可能モード(電源入れ直し直後など)のときのみ成功する。
    public static func pair(_ address: String, timeout: TimeInterval = 15) throws {
        let device = try device(for: address)
        if device.isPaired(), device.isConnected() { return }

        do {
            try performPairing(device, timeout: timeout)
        } catch {
            // 古いペアリング情報が邪魔している可能性がある場合のみ、削除して一度だけやり直す。
            // 先に削除すると、やり直しにも失敗したときにペアリングを失うため後から行う
            guard device.isPaired() else { throw error }
            try? unpair(device)
            try performPairing(device, timeout: timeout)
        }
    }

    static func performPairing(_ device: IOBluetoothDevice, timeout: TimeInterval) throws {
        let delegate = PairDelegate()
        guard let pairing = IOBluetoothDevicePair(device: device) else {
            throw PadError.commandFailed("ペアリングを開始できませんでした")
        }
        pairing.delegate = delegate
        let status = pairing.start()
        guard status == kIOReturnSuccess else {
            throw PadError.commandFailed("ペアリングを開始できませんでした (IOReturn: \(String(format: "0x%08x", status)))")
        }

        // IOBluetoothDevicePair のコールバックは呼び出したスレッドのランループに届く
        let deadline = Date().addingTimeInterval(timeout)
        while !delegate.finished, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        pairing.stop()

        guard delegate.finished else {
            throw PadError.timeout("ペアリングがタイムアウトしました。トラックパッドの電源と距離を確認してください")
        }
        guard delegate.result == kIOReturnSuccess else {
            throw PadError.commandFailed("ペアリングに失敗しました (IOReturn: \(String(format: "0x%08x", delegate.result)))")
        }
    }

    /// ペアリング情報を削除する。IOBluetoothDevice の非公開 API `remove` を使う(blueutil と同じ方法)。
    static func unpair(_ device: IOBluetoothDevice) throws {
        let selector = NSSelectorFromString("remove")
        guard device.responds(to: selector) else {
            throw PadError.commandFailed("この macOS ではペアリング解除 API が利用できません")
        }
        device.perform(selector)
    }

    /// 接続中のデバイスのペアリングを解除する。
    ///
    /// 接続中に解除するとトラックパッドに解除が伝わり、発見可能モードに入る。
    /// これが切り替えの要で、受け取る側の Mac はこの直後にペアリングできる。
    /// 未接続のまま解除してもトラックパッドには伝わらず、発見可能にならない。
    ///
    /// `remove` は無線越しに非同期で伝わるため、呼び出し後すぐに返ると受け取る側の
    /// 最初のペアリング試行が実際の切断より先に走ってしまう。実際に切断状態になる
    /// (または上限時間が経つ)まで待ってから返す。
    public static func release(_ address: String) throws {
        let device = try device(for: address)
        if !device.isConnected() {
            _ = tryOpenConnection(device, within: 5)
        }
        Log.switch.info("release: 解除開始 \(address, privacy: .public)")
        try unpair(device)
        let confirmed = waitUntilDisconnected(device, within: 3)
        Log.switch.info("release: 切断確認 \(confirmed ? "済み" : "タイムアウト", privacy: .public)")
    }

    static func waitUntilDisconnected(_ device: IOBluetoothDevice, within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while device.isConnected(), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !device.isConnected()
    }

    /// 周辺の発見可能な Bluetooth デバイスを探索して返す。診断用。
    public static func discover(duration: UInt8 = 8) throws -> [BTDevice] {
        let delegate = InquiryDelegate()
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: delegate) else {
            throw PadError.commandFailed("デバイス探索を開始できませんでした")
        }
        inquiry.inquiryLength = duration
        inquiry.updateNewDeviceNames = true
        let status = inquiry.start()
        guard status == kIOReturnSuccess else {
            throw PadError.commandFailed("デバイス探索を開始できませんでした (IOReturn: \(String(format: "0x%08x", status)))")
        }
        let deadline = Date().addingTimeInterval(TimeInterval(duration) + 10)
        while !delegate.done, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        inquiry.stop()
        return delegate.found.compactMap { device in
            guard let address = device.addressString else { return nil }
            return BTDevice(
                name: device.name ?? "(名称不明)",
                address: address,
                isConnected: device.isConnected(),
                isTrackpad: looksLikeTrackpad(device)
            )
        }
    }

    final class InquiryDelegate: NSObject, IOBluetoothDeviceInquiryDelegate {
        var found: [IOBluetoothDevice] = []
        var done = false

        @objc func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
            if let device { found.append(device) }
        }

        @objc func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
            done = true
        }
    }

    /// ペアリング処理の完了待ちと、SSP の確認要求への自動応答を行うデリゲート。
    final class PairDelegate: NSObject, IOBluetoothDevicePairDelegate {
        var finished = false
        var result: IOReturn = kIOReturnSuccess

        func devicePairingFinished(_ sender: Any!, error: IOReturn) {
            result = error
            finished = true
        }

        func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
            (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
        }
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
