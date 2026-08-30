import SwiftUI

struct PianoRollView: View {
    let song: MIDISong
    let currentTime: TimeInterval
    let activeIDs: Set<Int>
    var onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { geo in
            let layout = makeLayout(size: geo.size)
            Canvas { ctx, size in
                drawGrid(ctx: ctx, size: size, layout: layout)
                drawNotes(ctx: ctx, size: size, layout: layout)
                drawPlayhead(ctx: ctx, size: size, layout: layout)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(time(atX: value.location.x, width: geo.size.width, layout: layout))
                    }
            )
        }
    }

    private struct Layout {
        let pitchLo: Int
        let pitchHi: Int
        let pitchCount: Int
        let windowStart: TimeInterval
        let window: TimeInterval
        let rowH: CGFloat
        let leftGutter: CGFloat
    }

    private func makeLayout(size: CGSize) -> Layout {
        var lo = Int(song.pitchMin) - 2
        var hi = Int(song.pitchMax) + 2
        lo = max(21, lo)
        hi = min(108, max(hi, lo + 12))
        let count = max(1, hi - lo + 1)

        let duration = max(song.duration, 0.01)
        let window: TimeInterval
        let start: TimeInterval
        if duration <= 40 {
            window = duration
            start = 0
        } else {
            window = min(duration, 16)
            let target = currentTime - window * 0.25
            start = min(max(0, target), max(0, duration - window))
        }

        return Layout(
            pitchLo: lo,
            pitchHi: hi,
            pitchCount: count,
            windowStart: start,
            window: window,
            rowH: max(3, (size.height - 8) / CGFloat(count)),
            leftGutter: 36
        )
    }

    private func drawGrid(ctx: GraphicsContext, size: CGSize, layout: Layout) {
        let usable = size.width - layout.leftGutter
        for i in 0..<layout.pitchCount {
            let pitch = layout.pitchHi - i
            let y = 4 + CGFloat(i) * layout.rowH
            if MIDIFile.isBlackKey(pitch) {
                var row = Path()
                row.addRect(CGRect(x: layout.leftGutter, y: y, width: usable, height: layout.rowH))
                ctx.fill(row, with: .color(Color.primary.opacity(0.045)))
            }
            if pitch % 12 == 0 {
                var line = Path()
                line.move(to: CGPoint(x: layout.leftGutter, y: y + layout.rowH))
                line.addLine(to: CGPoint(x: size.width, y: y + layout.rowH))
                ctx.stroke(line, with: .color(Color.primary.opacity(0.08)), lineWidth: 1)

                ctx.draw(
                    Text(MIDIFile.noteName(UInt8(pitch)))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.secondary),
                    at: CGPoint(x: layout.leftGutter / 2, y: y + layout.rowH / 2),
                    anchor: .center
                )
            }
        }

        let beat = max(song.beatDuration, 0.05)
        let bar = beat * Double(max(1, song.numerator))
        var t = ceil(layout.windowStart / beat) * beat
        let end = layout.windowStart + layout.window
        while t <= end + 0.0001 {
            let x = xPos(for: t, width: size.width, layout: layout)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 4))
            line.addLine(to: CGPoint(x: x, y: size.height - 4))
            let rem = t.truncatingRemainder(dividingBy: bar)
            let isBar = rem < 0.02 || abs(bar - rem) < 0.02
            ctx.stroke(
                line,
                with: .color(Color.primary.opacity(isBar ? 0.16 : 0.06)),
                lineWidth: isBar ? 1.0 : 0.5
            )
            t += beat
        }
    }

    private func drawNotes(ctx: GraphicsContext, size: CGSize, layout: Layout) {
        let h = max(2, layout.rowH - 2)
        let windowEnd = layout.windowStart + layout.window
        let notes = song.notes
        guard !notes.isEmpty else { return }
        var lo = 0
        var hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].start < layout.windowStart - 32 { lo = mid + 1 } else { hi = mid }
        }
        for i in lo..<notes.count {
            let note = notes[i]
            if note.start > windowEnd { break }
            if note.end < layout.windowStart { continue }
            let pitch = Int(note.pitch)
            if pitch < layout.pitchLo || pitch > layout.pitchHi { continue }

            let x0 = xPos(for: note.start, width: size.width, layout: layout)
            let x1 = xPos(for: note.end, width: size.width, layout: layout)
            let w = max(2, x1 - x0)
            let row = layout.pitchHi - pitch
            let y = 4 + CGFloat(row) * layout.rowH + (layout.rowH - h) / 2
            let rect = CGRect(x: x0, y: y, width: w, height: h)
            let color = TrackPalette.color(for: note.track)
            let lit = activeIDs.contains(note.id)
            let path = Path(roundedRect: rect, cornerRadius: min(3, h / 2))
            ctx.fill(path, with: .color(color.opacity(lit ? 0.95 : 0.72)))
            if lit {
                ctx.stroke(path, with: .color(Color.white.opacity(0.55)), lineWidth: 1)
            }
        }
    }

    private func drawPlayhead(ctx: GraphicsContext, size: CGSize, layout: Layout) {
        let x = xPos(for: currentTime, width: size.width, layout: layout)
        var line = Path()
        line.move(to: CGPoint(x: x, y: 2))
        line.addLine(to: CGPoint(x: x, y: size.height - 2))
        let playhead = Color(red: 0.96, green: 0.55, blue: 0.28)
        ctx.stroke(line, with: .color(playhead), lineWidth: 1.5)
        var head = Path()
        head.addEllipse(in: CGRect(x: x - 4, y: 2, width: 8, height: 8))
        ctx.fill(head, with: .color(playhead))
    }

    private func xPos(for time: TimeInterval, width: CGFloat, layout: Layout) -> CGFloat {
        let usable = max(1, width - layout.leftGutter)
        let u = (time - layout.windowStart) / max(layout.window, 0.001)
        return layout.leftGutter + CGFloat(u) * usable
    }

    private func time(atX x: CGFloat, width: CGFloat, layout: Layout) -> TimeInterval {
        let usable = max(1, width - layout.leftGutter)
        let u = Double((x - layout.leftGutter) / usable)
        return min(max(layout.windowStart + u * layout.window, 0), song.duration)
    }
}
