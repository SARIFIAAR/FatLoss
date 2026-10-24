import Foundation
import CoreBluetooth

/// Runs native RingProtocol commands on the already-connected ring peripheral by temporarily taking over
/// its CBPeripheralDelegate (the QCBandSDK normally holds it) and restoring it when done. Safe ONLY while
/// no SDK command is in flight — the bridge enqueues direct commands on the same serial queue as SDK
/// commands, which guarantees that. One command at a time per instance.
///
/// CoreBluetooth-only: compiles for the simulator too (it just never has a peripheral there).
final class RingDirect: NSObject {

    enum DirectError: LocalizedError {
        case busy, timeout, characteristicsMissing, writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .busy: return "a direct command is already running"
            case .timeout: return "direct command timed out"
            case .characteristicsMissing: return "ring UART characteristics not found"
            case .writeFailed(let s): return "write failed: \(s)"
            }
        }
    }

    private let peripheral: CBPeripheral
    private let log: (String) -> Void
    private weak var savedDelegate: CBPeripheralDelegate?
    private var pendingPacket: Data?
    private var onFrame: ((Data) -> Bool)?       // return true = command finished
    private var completion: ((Error?) -> Void)?
    private var timeoutWork: DispatchWorkItem?

    init(peripheral: CBPeripheral, log: @escaping (String) -> Void) {
        self.peripheral = peripheral
        self.log = log
    }

    /// Send one 16-byte command packet and stream every notify frame to `onFrame` until it returns true
    /// (finished) or `timeout` elapses. The peripheral delegate is restored before `completion` runs.
    func run(_ packet: Data, timeout: TimeInterval,
             onFrame: @escaping (Data) -> Bool,
             completion: @escaping (Error?) -> Void) {
        guard self.completion == nil else { completion(DirectError.busy); return }
        guard peripheral.state == .connected else { completion(DirectError.characteristicsMissing); return }
        self.onFrame = onFrame
        self.completion = completion
        savedDelegate = peripheral.delegate
        peripheral.delegate = self

        let work = DispatchWorkItem { [weak self] in self?.finish(DirectError.timeout) }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)

        if let (w, n) = uartChars() {
            send(packet, write: w, notify: n)
        } else {
            // The SDK has usually discovered everything already; if not, discover just the UART service.
            pendingPacket = packet
            peripheral.discoverServices([CBUUID(string: RingProtocol.serviceUUID)])
        }
    }

    // MARK: internals

    private func uartChars() -> (write: CBCharacteristic, notify: CBCharacteristic)? {
        guard let svc = (peripheral.services ?? []).first(where: { $0.uuid == CBUUID(string: RingProtocol.serviceUUID) }),
              let w = (svc.characteristics ?? []).first(where: { $0.uuid == CBUUID(string: RingProtocol.writeUUID) }),
              let n = (svc.characteristics ?? []).first(where: { $0.uuid == CBUUID(string: RingProtocol.notifyUUID) })
        else { return nil }
        return (w, n)
    }

    private func send(_ packet: Data, write: CBCharacteristic, notify: CBCharacteristic) {
        if !notify.isNotifying { peripheral.setNotifyValue(true, for: notify) }
        let type: CBCharacteristicWriteType = write.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(packet, for: write, type: type)
    }

    private func finish(_ error: Error?) {
        guard let cb = completion else { return }
        timeoutWork?.cancel(); timeoutWork = nil
        completion = nil; onFrame = nil; pendingPacket = nil
        peripheral.delegate = savedDelegate   // hand the link back to the SDK
        savedDelegate = nil
        cb(error)
    }
}

extension RingDirect: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard completion != nil else { return }
        guard error == nil,
              let svc = (peripheral.services ?? []).first(where: { $0.uuid == CBUUID(string: RingProtocol.serviceUUID) })
        else { finish(DirectError.characteristicsMissing); return }
        peripheral.discoverCharacteristics([CBUUID(string: RingProtocol.writeUUID),
                                            CBUUID(string: RingProtocol.notifyUUID)], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard completion != nil else { return }
        guard error == nil, let packet = pendingPacket, let (w, n) = uartChars()
        else { finish(DirectError.characteristicsMissing); return }
        pendingPacket = nil
        send(packet, write: w, notify: n)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error, completion != nil { finish(DirectError.writeFailed(error.localizedDescription)) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard completion != nil, error == nil,
              characteristic.uuid == CBUUID(string: RingProtocol.notifyUUID),
              let data = characteristic.value else { return }
        if onFrame?(data) == true { finish(nil) }
    }
}
