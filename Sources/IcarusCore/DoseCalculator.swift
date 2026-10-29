import Foundation

/// Dose arithmetic over a forecast curve and the clock: how long a target takes
/// from a given minute, which block of a window is the shortest, whether a
/// window is worth going out for at all, when the next one is, whether the dose
/// is UVA-heavy, and what is left of a window that has partly passed (R4, R17,
/// R18).
///
/// Everything here is pure: the same curve, clock and target always give the
/// same answer.
public enum DoseCalculator {
    /// The shortest time from `start` that delivers `targetSED`, in minutes,
    /// interpolated inside the last minute so the answer is not rounded up to a
    /// whole one. Nil when the curve never reaches the target, or when reaching
    /// it would run past `notAfter` — the interpolated end is what is compared,
    /// not the whole minute containing it.
    public static func durationFrom(
        _ start: Date,
        targetSED: SED,
        curve: ForecastCurve,
        notAfter: Date
    ) -> Double? {
        guard targetSED > 0 else { return start <= notAfter ? 0 : nil }
        let prefix = curve.prefixSED
        let offset = start.timeIntervalSince(curve.prefixStart) / 60
        let goal = curve.prefixValue(at: start) + targetSED
        let firstIndex = max(0, Int(offset.rounded(.up)))
        guard firstIndex < prefix.count, let last = prefix.last, last >= goal - tolerance else { return nil }

        var low = firstIndex
        var high = prefix.count - 1
        while low < high {
            let middle = (low + high) / 2
            if prefix[middle] >= goal {
                high = middle
            } else {
                low = middle + 1
            }
        }
        guard low >= 1, prefix[low] >= goal - tolerance else { return nil }

        let previousOffset = max(Double(low - 1), offset)
        let previousValue = Double(low - 1) >= offset ? prefix[low - 1] : goal - targetSED
        let span = Double(low) - previousOffset
        let gained = prefix[low] - previousValue
        let endOffset = gained > 0 && span > 0
            ? previousOffset + span * (goal - previousValue) / gained
            : Double(low)
        let minutes = max(0, endOffset - offset)
        guard start.addingTimeInterval(minutes * 60) <= notAfter.addingTimeInterval(tolerance) else { return nil }
        return minutes
    }

    /// The shortest block inside `within` that delivers `targetSED`, never
    /// starting before `now`. Ties — a flat curve makes every start equal — go
    /// to the block whose middle is closest to solar noon.
    public static func bestSubWindow(
        curve: ForecastCurve,
        within: Window,
        now: Date,
        targetSED: SED,
        tunables _: Tunables
    ) -> Window? {
        guard let usable = clip(within, toStartNoEarlierThan: now), let coarse = bestStart(
            curve: curve, searching: usable, step: 60, targetSED: targetSED, notAfter: usable.end
        ) else { return nil }
        // The minute grid finds the right minute; a second pass at one-second
        // steps around it finds the start inside that minute, which is what
        // makes a block on a rising curve end at the window's end rather than
        // up to a minute early.
        let refine = Window(
            start: max(usable.start, coarse.start.addingTimeInterval(-60)),
            end: min(usable.end, coarse.start.addingTimeInterval(60))
        )
        let best = bestStart(
            curve: curve, searching: refine, step: 1, targetSED: targetSED, notAfter: usable.end
        ) ?? coarse
        return Window(start: best.start, end: best.start.addingTimeInterval(best.minutes * 60))
    }

    /// Whether a window, from now on, can deliver enough of the target to be
    /// worth going out for.
    public static func isViable(
        curve: ForecastCurve,
        window: Window,
        now: Date,
        targetSED: SED,
        tunables: Tunables
    ) -> Bool {
        guard let usable = clip(window, toStartNoEarlierThan: now) else { return false }
        let bar = tunables.viabilityFraction * targetSED
        guard bar > 0 else { return true }
        return curve.sed(from: usable.start, to: usable.end) >= bar
    }

    /// The next window, searched hour by hour, that could deliver a viable
    /// share of the target before its day is out. Never looks — or starts —
    /// past the end of the forecast.
    public static func nextViableWindow(
        curve: ForecastCurve,
        after: Date,
        targetSED: SED,
        tunables: Tunables
    ) -> Window? {
        let bar = tunables.viabilityFraction * targetSED
        var candidate = after
        while candidate <= curve.horizonEnd {
            let dayEnd = min(curve.day(candidate).end(), curve.horizonEnd)
            if dayEnd > candidate {
                let reach = durationFrom(candidate, targetSED: bar, curve: curve, notAfter: dayEnd)
                if let minutes = reach {
                    return Window(start: candidate, end: candidate.addingTimeInterval(minutes * 60))
                }
            }
            candidate = candidate.addingTimeInterval(3600)
        }
        return nil
    }

    /// A window whose middle sits far from solar noon takes a comparatively
    /// UVA-heavy dose (R18).
    public static func isUVAHeavy(window: Window, solarNoon: Date, tunables: Tunables) -> Bool {
        let middle = window.start.addingTimeInterval(window.minutes * 30)
        return abs(middle.timeIntervalSince(solarNoon)) > tunables.uvaHeavyHoursFromNoon * 3600
    }

    /// The part of a window still ahead. Nil once it has passed entirely (R17).
    public static func clip(_ window: Window, toStartNoEarlierThan now: Date) -> Window? {
        guard window.end > now else { return nil }
        return Window(start: max(window.start, now), end: window.end)
    }

    private static let tolerance = 1e-6

    /// One candidate block: where it starts, how long it runs, and how far its
    /// middle sits from solar noon — the tie-breaker.
    private struct Candidate {
        let start: Date
        let minutes: Double
        let offNoon: Double
    }

    /// The start inside `searching` on a `step`-second grid whose block is
    /// shortest, ties going to the block centred nearest solar noon.
    private static func bestStart(
        curve: ForecastCurve,
        searching: Window,
        step: Double,
        targetSED: SED,
        notAfter: Date
    ) -> Candidate? {
        var best: Candidate?
        var start = searching.start
        while start <= searching.end {
            if let minutes = durationFrom(start, targetSED: targetSED, curve: curve, notAfter: notAfter) {
                let middle = start.addingTimeInterval(minutes * 30)
                let noon = curve.solarNoon(on: curve.day(start))
                let candidate = Candidate(
                    start: start, minutes: minutes, offNoon: abs(middle.timeIntervalSince(noon))
                )
                if let current = best {
                    let shorter = minutes < current.minutes - tolerance
                    let tied = minutes < current.minutes + tolerance && candidate.offNoon < current.offNoon
                    if shorter || tied {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
            start = start.addingTimeInterval(step)
        }
        return best
    }
}
