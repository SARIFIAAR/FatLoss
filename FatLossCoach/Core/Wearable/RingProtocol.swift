import Foundation

// Native implementation of the ring's BLE wire protocol. The VY28C is a Colmi R02 platform (Oudmon ODM);
// the protocol below was validated byte-for-byte against three independent sources — the official QRing
// Android APK decompile, tahnok/colmi_r02_client (MIT) and robinojw/openring (MIT) — see
// docs/qring-sdk-teardown.md §12. This layer is pure packing/parsing: no CoreBluetooth, no vendor
// framework, compiles in every build (simulator included) and is unit-testable.
//
// Why it exists: the vendor QCBandSDK retrieves history unreliably and never exposes the timestamp-based
// opcode-21 read the official app uses for TODAY's all-day HR series. We speak the protocol ourselves,
// one command at a time, with our own retry/reassembly — the SDK stays as fallback.
enum RingProtocol {

    // Command channel (Nordic-UART style). 16-byte packets both ways.
    static let serviceUUID = "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E"
    static let writeUUID   = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    static let notifyUUID  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

    // Big Data channel — variable-length reads (sleep 0x27, SpO₂ history 0x2A, temp series 0x25/0x26).
    // The iOS SDK's ODM_DFU_Operation enum is this channel's dataId map.
    static let bigDataServiceUUID = "DE5BF728-D711-4E47-AF26-65E3012A5DC7"
    static let bigDataWriteUUID   = "DE5BF72A-D711-4E47-AF26-65E3012A5DC7"
    static let bigDataNotifyUUID  = "DE5BF729-D711-4E47-AF26-65E3012A5DC7"

    enum Cmd: UInt8 {
        case setTime = 1
        case battery = 3
        case reboot = 8
        case blink = 16
        case heartRateLog = 21    // timestamped full-day HR series — the read the vendor SDK hides
        case hrSettings = 22
        case stress = 55
        case hrv = 57
        case steps = 67
        case realTimeStart = 105
        case realTimeStop = 106
    }

    /// 16-byte command packet: [cmd][payload ≤14, zero-padded][checksum = sum of first 15 bytes & 0xFF].
    static func packet(_ cmd: Cmd, payload: [UInt8] = []) -> Data {
        precondition(payload.count <= 14, "payload must fit in 14 bytes")
        var b = [UInt8](repeating: 0, count: 16)
        b[0] = cmd.rawValue
        for (i, v) in payload.enumerated() { b[i + 1] = v }
        b[15] = UInt8(b[0..<15].reduce(0) { $0 + Int($1) } & 0xFF)
        return Data(b)
    }

    /// The ring labels days as "local midnight expressed as UTC": the official app sends
    /// localMidnightUnix + tzOffsetSeconds and subtracts the offset back when parsing responses.
    static func ringTimestamp(forDayOf date: Date,
                              calendar: Calendar = .current,
                              timeZone: TimeZone = .current) -> UInt32 {
        let midnight = calendar.startOfDay(for: date)
        let shifted = Int(midnight.timeIntervalSince1970) + timeZone.secondsFromGMT(for: midnight)
        return UInt32(clamping: shifted)
    }

    /// Inverse of `ringTimestamp` for timestamps received from the ring.
    static func dateFromRingTimestamp(_ ts: UInt32, timeZone: TimeZone = .current) -> Date {
        let approx = Date(timeIntervalSince1970: TimeInterval(ts))
        return Date(timeIntervalSince1970: TimeInterval(Int(ts) - timeZone.secondsFromGMT(for: approx)))
    }

    /// Opcode-21 request: full-day HR series (288 × 5-min samples) for the day containing `day`.
    static func heartRateLogRequest(day: Date) -> Data {
        let ts = ringTimestamp(forDayOf: day)
        return packet(.heartRateLog, payload: [UInt8(ts & 0xFF), UInt8((ts >> 8) & 0xFF),
                                               UInt8((ts >> 16) & 0xFF), UInt8((ts >> 24) & 0xFF)])
    }

    // MARK: Big Data channel framing (not yet wired into sync — sleep 0x27 is the next consumer)

    static let bigDataMagic: UInt8 = 0xBC
    enum BigDataID: UInt8 {
        case tempSeries = 0x25, tempManual = 0x26, sleep = 0x27, manualHR = 0x28, spo2History = 0x2A
    }

    /// Read-request: [0xBC][dataId][len=1 LE][crc sentinel 0x00FF][payload 0xFF = "all retained days"].
    static func bigDataRequest(_ id: BigDataID) -> Data {
        Data([bigDataMagic, id.rawValue, 0x01, 0x00, 0xFF, 0x00, 0xFF])
    }
}

/// One decoded day of the opcode-21 heart-rate log.
struct RingHeartRateLog {
    let dayStart: Date          // local midnight of the returned day
    let intervalMinutes: Int    // sample spacing (default 5)
    let samples: [Int]          // one slot per interval from midnight; 0 = no reading in that slot
}

/// State machine for the opcode-21 multi-packet response. Feed every 16-byte notify frame; frames for
/// other commands are ignored. Wire format (validated against the APK's ReadHeartRateRsp and tahnok's
/// parser, which agree byte-for-byte):
///   sub_type (byte[1]) 0xFF = no data for that day
///   0 = header {byte[2] = packet count, byte[3] = interval minutes}
///   1 = {bytes[2..5] = uint32 LE ring-timestamp, bytes[6..14] = first 9 samples}
///   2… = 13 samples each; ends at sub_type == count−1, or at sub_type 23 on a today-read (partial day)
final class RingHeartRateLogParser {
    enum Outcome {
        case waiting
        case done(RingHeartRateLog)
        case noData
    }

    private let requestedToday: Bool
    private var expectedPackets = 0
    private var intervalMinutes = 5
    private var raw: [UInt8] = []
    private var dayStart: Date?
    private var headerSeen = false

    init(requestedToday: Bool) { self.requestedToday = requestedToday }

    func feed(_ frame: Data) -> Outcome {
        guard frame.count == 16, frame[frame.startIndex] == RingProtocol.Cmd.heartRateLog.rawValue else { return .waiting }
        let b = [UInt8](frame)
        let sub = b[1]
        switch sub {
        case 0xFF:
            return .noData
        case 0:
            headerSeen = true
            expectedPackets = Int(b[2])
            intervalMinutes = max(1, Int(b[3]))
            raw.removeAll(keepingCapacity: true)
            return expectedPackets == 0 ? .noData : .waiting
        case 1 where headerSeen:
            let ts = UInt32(b[2]) | UInt32(b[3]) << 8 | UInt32(b[4]) << 16 | UInt32(b[5]) << 24
            dayStart = RingProtocol.dateFromRingTimestamp(ts)
            raw.append(contentsOf: b[6..<15])
            return .waiting
        case 23 where requestedToday && headerSeen:
            // Today-reads end with a 23 marker once the ring has sent all slots up to "now".
            return finish()
        case _ where headerSeen:
            raw.append(contentsOf: b[2..<15])
            return Int(sub) >= expectedPackets - 1 ? finish() : .waiting
        default:
            // No header yet: this is a leftover frame from a PREVIOUS day's still-streaming response
            // (seen on-device: they cascaded days 1–6 into instant false "no data"). Ignore until OUR
            // response starts with its sub-0 header.
            return .waiting
        }
    }

    private func finish() -> Outcome {
        let slotsPerDay = max(1, 24 * 60 / intervalMinutes)
        var samples = raw.map(Int.init)
        if samples.count > slotsPerDay { samples = Array(samples.prefix(slotsPerDay)) }
        if samples.count < slotsPerDay { samples.append(contentsOf: repeatElement(0, count: slotsPerDay - samples.count)) }
        let start = dayStart ?? Calendar.current.startOfDay(for: Date())
        // Slots after "now" on a today-read are future — force them empty (the official app does the same).
        if Calendar.current.isDateInToday(start) {
            let elapsed = Int(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date()))) / 60 / intervalMinutes
            for i in samples.indices where i > elapsed { samples[i] = 0 }
        }
        guard samples.contains(where: { $0 > 0 }) else { return .noData }
        return .done(RingHeartRateLog(dayStart: start, intervalMinutes: intervalMinutes, samples: samples))
    }
}

/// One decoded sleep night from the Big Data sleep read (dataId 0x27).
struct RingSleepNight {
    let daysAgo: Int           // 0 = last night (belongs to today's date key)
    let sleepStartMin: Int     // signed minutes after midnight (negative = fell asleep before midnight)
    let sleepEndMin: Int
    var lightMin = 0, deepMin = 0, remMin = 0, awakeMin = 0
    var asleepMin: Int { lightMin + deepMin + remMin }
}

extension RingProtocol {
    /// Parse the Big Data sleep payload (validated in openring against a real device capture):
    /// [nightCount] then per night [daysAgo][recordLen][startMin i16 LE][endMin i16 LE][stage pairs…],
    /// stage pair = [code][minutes], codes 2=light 3=deep 4=REM 5=awake. Empty/padding records
    /// (no stage pairs) are phantom nights — dropped. recordLen counts the bytes AFTER its own pair.
    static func parseSleepPayload(_ payload: [UInt8]) -> [RingSleepNight] {
        guard let count = payload.first, count > 0 else { return [] }
        func i16(_ o: Int) -> Int {
            let v = Int(payload[o]) | Int(payload[o + 1]) << 8
            return v >= 0x8000 ? v - 0x10000 : v
        }
        var nights: [RingSleepNight] = []
        var p = 1
        for _ in 0..<Int(count) {
            guard p + 6 <= payload.count else { break }
            let recordEnd = p + 2 + Int(payload[p + 1])
            var night = RingSleepNight(daysAgo: Int(payload[p]), sleepStartMin: i16(p + 2), sleepEndMin: i16(p + 4))
            var q = p + 6
            while q + 1 < recordEnd, q + 1 < payload.count {
                let minutes = Int(payload[q + 1])
                switch payload[q] {
                case 2: night.lightMin += minutes
                case 3: night.deepMin += minutes
                case 4: night.remMin += minutes
                case 5: night.awakeMin += minutes
                default: break
                }
                q += 2
            }
            if night.asleepMin + night.awakeMin > 0 { nights.append(night) }
            p = recordEnd > p ? recordEnd : p + 6
        }
        return nights
    }
}

/// Reassembles fragmented Big Data notifications: accumulate until 6-byte header + dataLen(bytes[2..3] LE)
/// bytes have arrived (same algorithm as the APK's LargeDataParser).
final class RingBigDataReassembler {
    private var buf: [UInt8] = []

    func reset() { buf.removeAll() }

    /// Returns (dataId, payload) once a full message is in; nil while still accumulating.
    func feed(_ chunk: Data) -> (id: UInt8, payload: [UInt8])? {
        if buf.isEmpty, chunk.first != RingProtocol.bigDataMagic { return nil }  // not a big-data stream
        buf.append(contentsOf: chunk)
        guard buf.count >= 6 else { return nil }
        let dataLen = Int(buf[2]) | Int(buf[3]) << 8
        guard buf.count >= 6 + dataLen else { return nil }
        let id = buf[1]
        let payload = Array(buf[6..<(6 + dataLen)])
        reset()
        return (id, payload)
    }
}
