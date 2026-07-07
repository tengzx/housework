import Foundation

/// Shared signal math for rep-level motion analysis, ported 1:1 from the
/// offline-validated prototype (scratchpad/onset_v2.py). Used by both the
/// template builder (batch, on a completed set) and the live onset detector
/// (streaming, on a trailing buffer) so their behaviour matches.
///
/// Input rows are `[t, ax, ay, az]` (t seconds; a = gravity-removed user
/// acceleration in g). Segmentation = peak-to-peak on the smoothed energy of
/// the acceleration norm; matching = DTW between 60-point resampled 3-axis
/// segments.
enum RepMotionMath {
    static let fs = 100.0
    static let resampleN = 60

    /// Split a motion buffer into per-motion (peak-to-peak) segments. Each
    /// returned segment is a list of `[ax, ay, az]` rows (raw, variable length).
    static func segments(_ rows: [[Double]]) -> [[[Double]]] {
        let n = rows.count
        guard n > Int(0.7 * fs) else { return [] }

        // Short-term energy of the acceleration norm, causally smoothed (~0.30s).
        let k = max(1, Int(0.30 * fs))
        var sm = [Double](repeating: 0, count: n)
        var acc = 0.0
        for i in 0..<n {
            let x = rows[i][1], y = rows[i][2], z = rows[i][3]
            let e = x * x + y * y + z * z
            acc += e
            if i >= k { acc -= (rows[i - k][1] * rows[i - k][1] + rows[i - k][2] * rows[i - k][2] + rows[i - k][3] * rows[i - k][3]) }
            sm[i] = acc / Double(min(i + 1, k))
        }

        let maxV = sm.max() ?? 0
        guard maxV > 0 else { return [] }
        let thr = maxV * 0.15
        let half = Int(0.25 * fs) / 2
        let minGap = Int(0.7 * fs)

        // Peaks: center of a 0.25s window is the window maximum and above thr.
        var peaks: [Int] = []
        var i = half
        while i < n - half {
            var isMax = true
            for j in (i - half)...(i + half) where sm[j] > sm[i] { isMax = false; break }
            if isMax && sm[i] >= thr {
                if let last = peaks.last, i - last < minGap {
                    if sm[i] > sm[last] { peaks[peaks.count - 1] = i }
                } else {
                    peaks.append(i)
                }
            }
            i += 1
        }

        guard peaks.count >= 2 else { return [] }
        var out: [[[Double]]] = []
        for j in 1..<peaks.count {
            let s = peaks[j - 1], e = peaks[j]
            let dur = Double(e - s) / fs
            if dur >= 0.7 && dur <= 5.0 {
                var seg: [[Double]] = []
                seg.reserveCapacity(e - s)
                for r in s..<e { seg.append([rows[r][1], rows[r][2], rows[r][3]]) }
                out.append(seg)
            }
        }
        return out
    }

    /// Peak of the causally-smoothed accel-norm energy over a buffer — the same
    /// quantity `segments` thresholds its peaks against, exposed on its own as an
    /// absolute "is the wrist actually moving?" gate. Near-motionless exercises
    /// (e.g. leg press: hands gripping, wrist still) sit far below any real
    /// wrist-driven rep, so a floor on this cleanly rejects "still" without
    /// touching arm work. Rows are `[t, ax, ay, az]`; units g².
    static func peakSmoothedEnergy(_ rows: [[Double]]) -> Double {
        let n = rows.count
        guard n > 0 else { return 0 }
        let k = max(1, Int(0.30 * fs))
        var acc = 0.0
        var maxV = 0.0
        for i in 0..<n {
            let x = rows[i][1], y = rows[i][2], z = rows[i][3]
            acc += x * x + y * y + z * z
            if i >= k { acc -= (rows[i - k][1] * rows[i - k][1] + rows[i - k][2] * rows[i - k][2] + rows[i - k][3] * rows[i - k][3]) }
            let v = acc / Double(min(i + 1, k))
            if v > maxV { maxV = v }
        }
        return maxV
    }

    /// Resample a variable-length 3-axis segment to `resampleN` points.
    static func resample(_ seg: [[Double]]) -> [[Double]] {
        let m = seg.count
        guard m >= 2 else { return [] }
        let n = resampleN
        var out = [[Double]](repeating: [0, 0, 0], count: n)
        for idx in 0..<n {
            let pos = Double(idx) * Double(m - 1) / Double(n - 1)
            let lo = Int(pos)
            let hi = min(lo + 1, m - 1)
            let frac = pos - Double(lo)
            for d in 0..<3 { out[idx][d] = seg[lo][d] * (1 - frac) + seg[hi][d] * frac }
        }
        return out
    }

    /// DTW distance between two resampled 3-axis segments, normalized by path
    /// length. Lower = more similar.
    static func dtw(_ a: [[Double]], _ b: [[Double]]) -> Double {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return .infinity }
        var prev = [Double](repeating: .infinity, count: m + 1)
        prev[0] = 0
        for i in 1...n {
            var cur = [Double](repeating: .infinity, count: m + 1)
            let ai = a[i - 1]
            for j in 1...m {
                let bj = b[j - 1]
                let dx = ai[0] - bj[0], dy = ai[1] - bj[1], dz = ai[2] - bj[2]
                let cost = (dx * dx + dy * dy + dz * dz).squareRoot()
                cur[j] = cost + Swift.min(prev[j], cur[j - 1], prev[j - 1])
            }
            prev = cur
        }
        return prev[m] / Double(n + m)
    }

    /// Pick a representative rep from a completed set's motion to use as the
    /// exercise template: the median segment by total absolute amplitude.
    static func representativeTemplate(from setRows: [[Double]]) -> [[Double]]? {
        let segs = segments(setRows).map(resample).filter { !$0.isEmpty }
        guard !segs.isEmpty else { return nil }
        let sorted = segs.sorted { absSum($0) < absSum($1) }
        return sorted[sorted.count / 2]
    }

    private static func absSum(_ seg: [[Double]]) -> Double {
        var s = 0.0
        for row in seg { s += abs(row[0]) + abs(row[1]) + abs(row[2]) }
        return s
    }
}
