import CoreBluetooth
import Foundation
import PadSwitchCore

// padswitch-cli: PadSwitch の Bluetooth 操作 CLI。
// アプリからローカル/SSH 越しの両方で使われる。
//
// 終了コード: 0=成功, 1=エラー, 2=使い方誤り, 3=(status) 未接続

let version = "1.1.0"

func usage() -> Never {
    let text = """
    usage:
      padswitch-cli list [--json]        ペアリング済みデバイス一覧(トラックパッド優先)
      padswitch-cli status <address>     接続状態 (exit 0=接続中, 3=未接続)
      padswitch-cli connect <address>    接続 (必要なら自動でペアリング)
      padswitch-cli pair <address>       ペアリングし直す
      padswitch-cli disconnect <address> 切断
      padswitch-cli selfcheck            Bluetooth権限とペアリング一覧を表示
      padswitch-cli version
    """
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

func fail(_ error: Error) -> Never {
    let message = (error as? PadError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

switch command {
case "version":
    print(version)

case "selfcheck":
    // TCCの許可がないとペアリング一覧はエラーではなく空で返るため、権限状態を明示的に出力する
    let authText: String
    switch CBManager.authorization {
    case .allowedAlways: authText = "allowed"
    case .denied: authText = "denied"
    case .restricted: authText = "restricted"
    default: authText = "notDetermined"
    }
    print("bluetooth-authorization: \(authText)")
    for device in BluetoothController.pairedDevices() {
        print("paired: \(device.address) \(device.name)")
    }

case "list":
    let devices = BluetoothController.pairedDevices()
    if args.contains("--json") {
        let items = devices.map { device in
            [
                "name": device.name,
                "address": device.address,
                "connected": device.isConnected,
                "trackpad": device.isTrackpad,
            ] as [String: Any]
        }
        let data = try! JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    } else {
        for device in devices {
            let mark = device.isConnected ? "*" : " "
            let kind = device.isTrackpad ? "[trackpad]" : ""
            print("\(mark) \(device.address)  \(device.name) \(kind)")
        }
    }

case "status":
    guard args.count >= 2 else { usage() }
    do {
        let connected = try BluetoothController.isConnected(args[1])
        print(connected ? "connected" : "disconnected")
        exit(connected ? 0 : 3)
    } catch {
        fail(error)
    }

case "connect":
    guard args.count >= 2 else { usage() }
    do {
        try BluetoothController.connect(args[1])
        print("connected")
    } catch {
        fail(error)
    }

case "pair":
    guard args.count >= 2 else { usage() }
    do {
        try BluetoothController.pair(args[1])
        print("paired")
    } catch {
        fail(error)
    }

case "release":
    guard args.count >= 2 else { usage() }
    do {
        try BluetoothController.release(args[1])
        print("released")
    } catch {
        fail(error)
    }

case "discover":
    do {
        for device in try BluetoothController.discover() {
            print("found: \(device.address) \(device.name)")
        }
        print("done")
    } catch {
        fail(error)
    }

case "disconnect":
    guard args.count >= 2 else { usage() }
    do {
        try BluetoothController.disconnect(args[1])
        print("disconnected")
    } catch {
        fail(error)
    }

default:
    usage()
}
