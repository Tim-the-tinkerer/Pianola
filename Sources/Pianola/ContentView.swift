import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var engine: MIDIEngine

    private let cardBg = Color(nsColor: .controlBackgroundColor)
    private let panelBg = Color(nsColor: .windowBackgroundColor)

    @State private var isDropTargeted = false
    @State private var selectedID: String?

    var body: some View {
        HStack(spacing: 0) {
            librarySidebar
                .frame(width: 232)
            Divider()
            mainPanel
        }
        .frame(minWidth: 860, minHeight: 580)
        .background(panelBg)
        .onAppear {
            engine.loadDefaultIfNeeded()
            if selectedID == nil {
                selectedID = engine.bundled.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pianolaOpenPanel)) { _ in
            engine.openPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pianolaOpenURL)) { note in
            if let url = note.object as? URL {
                selectedID = url.path
                engine.load(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pianolaTogglePlay)) { _ in
            engine.togglePlay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pianolaStop)) { _ in
            engine.stop()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                    .padding(10)
                    .background(Color.accentColor.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Sidebar

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Text("MIDI files")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(engine.bundled) { piece in
                        LibraryRow(
                            title: piece.title,
                            subtitle: piece.detail,
                            icon: "music.note.list",
                            isSelected: selectedID == piece.id,
                            isActive: engine.isPlaying && engine.fileName == piece.title
                        ) {
                            selectedID = piece.id
                            engine.loadBundled(piece)
                        }
                    }

                    if !engine.recents.isEmpty {
                        Text("RECENT")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .tracking(1.1)
                            .padding(.top, 12)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(engine.recents) { recent in
                            LibraryRow(
                                title: recent.name,
                                subtitle: recent.path,
                                icon: "doc",
                                isSelected: selectedID == recent.path,
                                isActive: engine.isPlaying && engine.fileName == recent.name
                            ) {
                                selectedID = recent.path
                                engine.load(url: recent.url)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            Button {
                engine.openPanel()
            } label: {
                Label("Open MIDI File…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .help("Open a .mid file (⌘O)")

            Text("Drop a MIDI file anywhere, or double-click one in Finder.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    // MARK: - Main

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            rollSection
            keyboardSection
            transport
            footerBar
        }
        .padding(18)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.song?.title.isEmpty == false ? engine.song!.title : (engine.fileName.isEmpty ? "Pianola" : engine.fileName))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            playButton
        }
        .padding(.bottom, 14)
    }

    private var statusLine: String {
        if let err = engine.errorMessage {
            return "Error · \(err)"
        }
        guard let song = engine.song else {
            return "Open a MIDI file to play"
        }
        let parts = [
            String(format: "%.0f BPM", song.tempoBPM),
            song.timeSignatureLabel,
            song.keySignature,
            formatCount(song.noteCount) + " notes",
            "\(song.tracks.count) " + (song.tracks.count == 1 ? "track" : "tracks"),
        ]
        let prefix = engine.isPlaying ? "Playing" : "Ready"
        return "\(prefix) · " + parts.joined(separator: " · ")
    }

    private var playButton: some View {
        Button {
            engine.togglePlay()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(engine.isPlaying ? "Pause" : "Play")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(engine.isPlaying
                          ? Color(red: 0.85, green: 0.42, blue: 0.22)
                          : Color(red: 0.78, green: 0.52, blue: 0.16))
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(engine.isPlaying ? "Pause (Space)" : "Play (Space)")
        .disabled(engine.song == nil)
    }

    private var rollSection: some View {
        Group {
            if let song = engine.song {
                PianoRollView(
                    song: song,
                    currentTime: displayedTime,
                    activeIDs: Set(engine.activeNotes().map(\.id)),
                    onSeek: { t in
                        engine.seek(to: t)
                    }
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardBg)
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("Drop a MIDI file here")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 12)
    }

    private var keyboardSection: some View {
        Group {
            if let song = engine.song {
                PianoKeyboardView(
                    pitchMin: Int(song.pitchMin),
                    pitchMax: Int(song.pitchMax),
                    active: engine.activePitches(),
                    preview: engine.previewPitch,
                    notes: engine.activeNotes(),
                    onNoteOn: { engine.noteOnPreview($0) },
                    onNoteOff: { engine.noteOffPreview($0) }
                )
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.10, blue: 0.09))
            }
        }
        .frame(height: 96)
        .padding(.bottom, 14)
    }

    private var transport: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    engine.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(engine.song == nil)
                .help("Stop")

                Button {
                    engine.skip(seconds: -5)
                } label: {
                    Image(systemName: "gobackward.5")
                }
                .buttonStyle(.bordered)
                .disabled(engine.song == nil)
                .help("Back 5 seconds")

                Button {
                    engine.skip(seconds: 5)
                } label: {
                    Image(systemName: "goforward.5")
                }
                .buttonStyle(.bordered)
                .disabled(engine.song == nil)
                .help("Forward 5 seconds")

                Text(formatTime(displayedTime))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { displayedTime },
                        set: { engine.seek(to: $0) }
                    ),
                    in: 0...max(engine.duration, 0.01)
                )
                .disabled(engine.song == nil)

                Text(formatTime(engine.duration))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Toggle(isOn: Binding(
                    get: { engine.looping },
                    set: { engine.looping = $0; engine.loopingDidChange() }
                )) {
                    Image(systemName: "repeat")
                }
                .toggleStyle(.button)
                .help("Loop")
                .disabled(engine.song == nil)
            }

            HStack(alignment: .center, spacing: 18) {
                labeledSlider(title: "Volume", value: volumeLabel) {
                    Slider(value: $engine.volume, in: 0...1)
                        .frame(maxWidth: 180)
                        .help("Output level")
                }

                labeledSlider(title: "Tempo", value: String(format: "%.2f×", engine.rate)) {
                    Slider(value: $engine.rate, in: 0.25...2.0)
                        .frame(maxWidth: 180)
                }

                Toggle(isOn: $engine.reverbEnabled) {
                    Text("Reverb")
                }
                .toggleStyle(.checkbox)
                .help("Chamber reverb on the General MIDI synth")

                Picker("Instrument", selection: Binding(
                    get: { engine.instrumentOverride.map { Int($0) } ?? -1 },
                    set: { engine.instrumentOverride = $0 < 0 ? nil : UInt8($0) }
                )) {
                    Text("As written").tag(-1)
                    Divider()
                    ForEach(GMInstruments.favorites, id: \.self) { program in
                        Text(GMInstruments.shortName(for: program)).tag(Int(program))
                    }
                    Divider()
                    ForEach(0..<GMInstruments.names.count, id: \.self) { i in
                        if !GMInstruments.favorites.contains(UInt8(i)) {
                            Text(GMInstruments.names[i]).tag(i)
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 160, maxWidth: 220)
                .help("As written keeps each track’s program, including Theremin when the file names it. Any other choice replaces every track.")
                .disabled(engine.song == nil)

                Spacer()
            }

            if let song = engine.song, !song.tracks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(song.tracks) { track in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(TrackPalette.color(for: track.id))
                                    .frame(width: 8, height: 8)
                                Text(track.name)
                                    .font(.caption)
                                Text(formatCount(track.noteCount))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(TrackPalette.color(for: track.id).opacity(0.12))
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBg)
        )
    }

    private var footerBar: some View {
        HStack {
            Text(footerLeft)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
            Text(engine.engineLabel)
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.top, 10)
    }

    private var footerLeft: String {
        guard let song = engine.song else { return "Standard MIDI · GM playback" }
        return "Format \(song.format) · \(song.ticksPerQuarter) TPQ · \(formatTime(song.duration))"
    }

    private var displayedTime: TimeInterval {
        engine.currentTime
    }

    private var volumeLabel: String {
        "\(Int(engine.volume * 100))%"
    }

    private func labeledSlider<Content: View>(
        title: String,
        value: String,
        @ViewBuilder slider: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            slider()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        }
        if n >= 10_000 {
            return String(format: "%.0fk", Double(n) / 1_000)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(max(0, t).rounded(.towardZero))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    } else if let s = item as? String {
                        url = URL(fileURLWithPath: s)
                    } else {
                        url = nil
                    }
                    guard let url, ["mid", "midi", "smf"].contains(url.pathExtension.lowercased()) else { return }
                    Task { @MainActor in
                        selectedID = url.path
                        engine.load(url: url)
                    }
                }
            }
        }
        return handled
    }
}

private struct LibraryRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isActive {
                    Circle()
                        .fill(Color(red: 0.85, green: 0.48, blue: 0.18))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    static let pianolaOpenPanel = Notification.Name("pianolaOpenPanel")
    static let pianolaOpenURL = Notification.Name("pianolaOpenURL")
    static let pianolaTogglePlay = Notification.Name("pianolaTogglePlay")
    static let pianolaStop = Notification.Name("pianolaStop")
}
