import Foundation
import PadSwitchCore

// padswitch-cli: PadSwitch の Bluetooth 操作 CLI。
// アプリからローカル/SSH 越しの両方で使われる。
//
// 終了コード: 0=成功, 1=エラー, 2=使い方誤り, 3=(status) 未接続

let version = "1.0.0"

func usage() -> Never {
    let text = """
    usage:
      padswitch-cli list [--json]        ペアリング済みデバイス一覧(トラックパッド優先)
      padswitch-cli status <address>     接続状態 (exit 0=接続中, 3=未接続)
      padswitch-cli connect <address>    接続 (確認できるまで待つ)
      padswitch-cli disconnect <address> 切断
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
