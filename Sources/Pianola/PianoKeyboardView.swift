import SwiftUI

struct PianoKeyboardView: View {
    let pitchMin: Int
    let pitchMax: Int
    let active: Set<UInt8>
    let preview: UInt8?
    let notes: [MIDINote]
    var onNoteOn: (UInt8) -> Void
    var onNoteOff: (UInt8) -> Void

    private var range: ClosedRange<Int> {
        let lo = max(21, min(pitchMin, pitchMax) - 2)
        let hi = min(108, max(pitchMin, pitchMax) + 2)
        var a = lo
        var b = max(hi, a + 16)
        while MIDIFile.isBlackKey(a) { a -= 1 }
        while MIDIFile.isBlackKey(b) { b += 1 }
        return max(21, a)...min(108, b)
    }

    private var whites: [Int] {
        range.filter { !MIDIFile.isBlackKey($0) }
    }

    var body: some View {
        GeometryReader { geo in
            let whiteWidth = geo.size.width / CGFloat(max(whites.count, 1))
            let whiteHeight = geo.size.height
            let blackWidth = whiteWidth * 0.62
            let blackHeight = whiteHeight * 0.62

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whites, id: \.self) { pitch in
                        WhiteKey(
                            pitch: pitch,
                            width: whiteWidth,
                            height: whiteHeight,
                            lit: isLit(pitch),
                            color: glowColor(for: pitch)
                        )
                        .contentShape(Rectangle())
                        .gesture(keyGesture(pitch))
                    }
                }

                ForEach(range.filter { MIDIFile.isBlackKey($0) }, id: \.self) { pitch in
                    let x = blackX(for: pitch, whiteWidth: whiteWidth)
                    BlackKey(
                        lit: isLit(pitch),
                        color: glowColor(for: pitch)
                    )
                    .frame(width: blackWidth, height: blackHeight)
                    .offset(x: x, y: 0)
                    .contentShape(Rectangle())
                    .gesture(keyGesture(pitch))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func isLit(_ pitch: Int) -> Bool {
        active.contains(UInt8(pitch)) || preview == UInt8(pitch)
    }

    private func glowColor(for pitch: Int) -> Color {
        if let preview, preview == UInt8(pitch) {
            return Color(red: 0.96, green: 0.74, blue: 0.32)
        }
        if let note = notes.first(where: { $0.pitch == UInt8(pitch) }) {
            return TrackPalette.color(for: note.track)
        }
        return Color(red: 0.96, green: 0.74, blue: 0.32)
    }

    private func blackX(for pitch: Int, whiteWidth: CGFloat) -> CGFloat {
        // Place the black key centered on the boundary between its surrounding whites.
        let leftWhite = whites.last { $0 < pitch } ?? pitch
        guard let idx = whites.firstIndex(of: leftWhite) else { return 0 }
        return CGFloat(idx + 1) * whiteWidth - (whiteWidth * 0.62) / 2
    }

    private func keyGesture(_ pitch: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if preview != UInt8(pitch) {
                    onNoteOn(UInt8(pitch))
                }
            }
            .onEnded { _ in
                onNoteOff(UInt8(pitch))
            }
    }
}

private struct WhiteKey: View {
    let pitch: Int
    let width: CGFloat
    let height: CGFloat
    let lit: Bool
    let color: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: lit
                            ? [color.opacity(0.95), color.opacity(0.7)]
                            : [Color(red: 0.99, green: 0.98, blue: 0.95), Color(red: 0.90, green: 0.88, blue: 0.84)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)

            if pitch % 12 == 0, width >= 14 {
                Text(MIDIFile.noteName(UInt8(pitch)))
                    .font(.system(size: min(9, width * 0.42), weight: .medium, design: .rounded))
                    .foregroundStyle(lit ? Color.white.opacity(0.9) : Color.black.opacity(0.35))
                    .padding(.bottom, 6)
            }
        }
        .frame(width: width, height: height)
        .scaleEffect(x: 1, y: lit ? 0.985 : 1, anchor: .top)
        .animation(.easeOut(duration: 0.06), value: lit)
    }
}

private struct BlackKey: View {
    let lit: Bool
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: lit
                        ? [color, color.opacity(0.75)]
                        : [Color(red: 0.16, green: 0.14, blue: 0.12), Color(red: 0.08, green: 0.07, blue: 0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.white.opacity(lit ? 0.35 : 0.12), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            .scaleEffect(x: 1, y: lit ? 0.97 : 1, anchor: .top)
            .animation(.easeOut(duration: 0.06), value: lit)
    }
}
