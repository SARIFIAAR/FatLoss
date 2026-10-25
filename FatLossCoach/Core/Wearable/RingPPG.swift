import Foundation

/// Raw-PPG signal processing: 25 Hz green-light PPG → beat detection → RR intervals → rMSSD (true HRV)
/// + mean HR. Pure Swift, no dependencies, sim-safe, unit-testable. This is the WHOOP-style HRV path
/// (the firmware "HRV" number is a proxy); scaffold stage — results are logged and stored as a capture,
/// not yet fed into Recovery (that needs nightly scheduling + validation, phase 4/5 of the WHOOP plan).
enum RingPPG {

    struct Analysis {
        let beats: Int
        let meanHR: Double        // bpm over the window
        let rmssd: Double         // ms — root mean square of successive RR differences
        let rrIntervals: [Double] // ms, after artifact gating
        let windowSeconds: Double
    }

    /// Analyze one capture window. `hz` is the sample rate (25 for this strap).
    /// Returns nil when the window is too short or too few clean beats are found.
    static func analyze(ppg raw: [Double], hz: Double = 25) -> Analysis? {
        guard raw.count >= Int(hz * 20) else { return nil }   // need ≥20 s

        // 1. Detrend: subtract a centered moving average (~0.6 s) to remove baseline wander.
        let window = max(3, Int(hz * 0.6))
        let detrended = subtractMovingAverage(raw, window: window)

        // 2. Adaptive peak detection: local maxima above a rolling threshold, min 0.33 s apart (≤180 bpm).
        let minGap = Int(hz / 3)
        let peaks = detectPeaks(detrended, minGap: minGap, hz: hz)
        guard peaks.count >= 10 else { return nil }

        // 3. RR intervals (ms), gated: physiologic range + reject >25% jumps vs the running median
        //    (motion artifacts / missed beats).
        var rr: [Double] = []
        for i in 1..<peaks.count {
            let ms = Double(peaks[i] - peaks[i - 1]) / hz * 1000
            guard ms >= 300, ms <= 2000 else { continue }
            if let last = rr.last, abs(ms - last) / last > 0.25 { continue }
            rr.append(ms)
        }
        guard rr.count >= 8 else { return nil }
        let meanRR = rr.reduce(0, +) / Double(rr.count)

        // Quality gate: the clean RR chain must account for most of the window's expected beats —
        // random noise yields sparse chance-survivors here, a real pulse yields near-full coverage.
        let expectedBeats = (Double(raw.count) / hz) / (meanRR / 1000)
        guard Double(rr.count) >= 0.5 * expectedBeats else { return nil }

        // 4. rMSSD + mean HR.
        var sumSq = 0.0
        for i in 1..<rr.count { let d = rr[i] - rr[i - 1]; sumSq += d * d }
        let rmssd = (sumSq / Double(rr.count - 1)).squareRoot()

        return Analysis(beats: peaks.count, meanHR: 60000 / meanRR, rmssd: rmssd,
                        rrIntervals: rr, windowSeconds: Double(raw.count) / hz)
    }

    /// rMSSD straight from a sampled RRI stream (the strap's one-key measure reports its live
    /// beat-to-beat interval ~1×/s — firmware-computed from the same PPG sensor). The sampled series
    /// under-counts beats, so this is an approximation; successive DISTINCT values are used.
    /// This is the VY28C path to true HRV — the raw-PPG stream is not supported by its firmware.
    static func rmssd(fromRRIms stream: [Double]) -> (rmssd: Double, usedIntervals: Int)? {
        var rr: [Double] = []
        for v in stream where v >= 300 && v <= 2000 {
            if v != rr.last { rr.append(v) }         // collapse repeated samples of the same beat
        }
        guard rr.count >= 8 else { return nil }
        var sumSq = 0.0
        for i in 1..<rr.count { let d = rr[i] - rr[i - 1]; sumSq += d * d }
        return ((sumSq / Double(rr.count - 1)).squareRoot(), rr.count)
    }

    // MARK: internals

    private static func subtractMovingAverage(_ x: [Double], window: Int) -> [Double] {
        let half = window / 2
        var prefix = [0.0]; prefix.reserveCapacity(x.count + 1)
        for v in x { prefix.append(prefix[prefix.count - 1] + v) }
        return x.indices.map { i in
            let lo = max(0, i - half), hi = min(x.count - 1, i + half)
            let mean = (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
            return x[i] - mean
        }
    }

    private static func detectPeaks(_ x: [Double], minGap: Int, hz: Double) -> [Int] {
        // Rolling amplitude threshold: 60% of the signal's std-dev over a ~4 s neighborhood.
        let n = x.count
        let segment = max(1, Int(hz * 4))
        var peaks: [Int] = []
        var lastPeak = -minGap
        for i in 1..<(n - 1) where x[i] > x[i - 1] && x[i] >= x[i + 1] {
            let lo = max(0, i - segment), hi = min(n - 1, i + segment)
            var sum = 0.0, sumSq = 0.0
            // cheap std-dev over the neighborhood (segment is small at 25 Hz)
            for j in lo...hi { sum += x[j]; sumSq += x[j] * x[j] }
            let count = Double(hi - lo + 1)
            let mean = sum / count
            let std = max(1e-9, (sumSq / count - mean * mean).squareRoot())
            guard x[i] > mean + 0.6 * std else { continue }
            if i - lastPeak < minGap {
                // keep the taller of the two contenders
                if let last = peaks.last, x[i] > x[last] { peaks[peaks.count - 1] = i; lastPeak = i }
                continue
            }
            peaks.append(i); lastPeak = i
        }
        return peaks
    }
}
