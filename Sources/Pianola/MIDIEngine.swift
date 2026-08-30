import AppKit
import AVFoundation
import AudioToolbox
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MIDIEngine: ObservableObject {
    static let shared = MIDIEngine()

    @Published private(set) var song: MIDISong?
    @Published private(set) var fileName = ""
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var looping = false
    @Published var rate: Float = 1.0 {
        didSet { resyncClock() }
    }
    @Published var volume: Double = 0.85 {
        didSet { applyVolume() }
    }
    @Published var reverbEnabled = true {
        didSet { applyReverb() }
    }
    /// `nil` keeps each track’s program from the file. Otherwise all channels use this GM patch.
    @Published var instrumentOverride: UInt8? = nil {
        didSet { applyInstrumentOverride() }
    }
    @Published var errorMessage: String?
    @Published private(set) var engineLabel = "—"
    @Published var recents: [RecentFile] = []
    @Published var previewPitch: UInt8?

    let bundled: [BundledPiece] = [
        BundledPiece(
            id: "generated-scale",
            title: "Generated Scale",
            detail: "C major · piano, bass, strings",
            fileName: "Generated Scale"
        ),
        BundledPiece(
            id: "c-major-scale",
            title: "C major scale",
            detail: "C major · longer study",
            fileName: "C major scale"
        ),
    ]

    private let audioEngine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private let gainNode = AVAudioMixerNode()
    private var synth: AVAudioUnit?
    private var synthReady = false
    private var tick: Timer?
    private var finishing = false
    private var seeking = false
    private var loadedURL: URL?

    private var clockAnchor: Date?
    private var clockTime: TimeInterval = 0
    private var lastDispatchTime: TimeInterval = 0
    private var sounding = Set<Int>()
    private var lastProgram: [UInt8: UInt8] = [:]

    private init() {
        recents = RecentFile.load()
        bootstrapAudio()
    }

    // MARK: - Library

    func loadBundled(_ piece: BundledPiece) {
        guard let url = MIDILibrary.url(named: piece.fileName) else {
            errorMessage = "Couldn’t find “\(piece.title)” in the app bundle."
            return
        }
        load(url: url)
    }

    func load(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        stop()
        errorMessage = nil
        finishing = false

        do {
            let parsed = try MIDIFile.parse(url: url)
            song = parsed
            fileName = url.deletingPathExtension().lastPathComponent
            duration = max(parsed.duration, 0.01)
            currentTime = 0
            loadedURL = url
            remember(url)
            engineLabel = synthReady ? "DLS Synth" : "Starting…"
        } catch {
            song = nil
            fileName = ""
            duration = 0
            errorMessage = error.localizedDescription
        }
    }

    func loadDefaultIfNeeded() {
        guard song == nil, let first = bundled.first else { return }
        loadBundled(first)
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open MIDI File"
        panel.allowedContentTypes = [.midi]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.load(url: url)
            }
        }
    }

    // MARK: - Transport

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard song != nil else { return }
        if !synthReady || synth == nil {
            errorMessage = "Synth isn’t ready yet — try Play again in a moment."
            return
        }
        errorMessage = nil
        finishing = false

        if currentTime >= duration - 0.04 {
            currentTime = 0
        }

        ensureEngineRunning()
        allSoundOff()
        lastProgram.removeAll()
        sounding.removeAll()
        applyVolume()
        sendPrograms()

        clockTime = currentTime
        lastDispatchTime = currentTime
        clockAnchor = Date()
        isPlaying = true
        startHeldNotes(at: currentTime)
        startTick()
    }

    func pause() {
        isPlaying = false
        clockAnchor = nil
        allSoundOff()
        sounding.removeAll()
        stopTick()
    }

    func stop() {
        isPlaying = false
        clockAnchor = nil
        currentTime = 0
        lastDispatchTime = 0
        finishing = false
        allSoundOff()
        sounding.removeAll()
        stopTick()
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), max(0, duration))
        seeking = true
        currentTime = clamped
        lastDispatchTime = clamped
        clockTime = clamped
        if isPlaying {
            clockAnchor = Date()
            allSoundOff()
            sounding.removeAll()
            applyVolume()
            startHeldNotes(at: clamped)
        }
        seeking = false
    }

    func skip(seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func beginScrub() {
        seeking = true
        if isPlaying {
            allSoundOff()
            sounding.removeAll()
        }
    }

    func scrub(to time: TimeInterval) {
        currentTime = min(max(0, time), max(0, duration))
    }

    func endScrub() {
        seeking = false
        seek(to: currentTime)
    }

    func activeNotes() -> [MIDINote] {
        song?.notesActive(at: currentTime) ?? []
    }

    func activePitches() -> Set<UInt8> {
        Set(activeNotes().map(\.pitch))
    }

    func loopingDidChange() {}

    // MARK: - Keyboard preview

    func noteOnPreview(_ pitch: UInt8) {
        previewPitch = pitch
        guard let au = synthAU else { return }
        applyVolume()
        let program = instrumentOverride ?? 0
        MusicDeviceMIDIEvent(au, 0xC0, UInt32(program), 0, 0)
        lastProgram[0] = program
        let vel = scaledVelocity(96)
        MusicDeviceMIDIEvent(au, 0x90, UInt32(pitch), vel, 0)
    }

    func noteOffPreview(_ pitch: UInt8) {
        if previewPitch == pitch { previewPitch = nil }
        guard let au = synthAU else { return }
        MusicDeviceMIDIEvent(au, 0x80, UInt32(pitch), 0, 0)
    }

    // MARK: - Audio setup

    private var synthAU: AudioUnit? { synth?.audioUnit }

    private func bootstrapAudio() {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_DLSSynth,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        AVAudioUnit.instantiate(with: desc, options: []) { [weak self] unit, _ in
            Task { @MainActor in
                guard let self else { return }
                if let unit {
                    self.attachSynth(unit)
                } else {
                    self.engineLabel = "No synth"
                    self.errorMessage = "Couldn’t open the macOS General MIDI synth."
                }
            }
        }
    }

    private func attachSynth(_ unit: AVAudioUnit) {
        synth = unit
        audioEngine.attach(unit)
        audioEngine.attach(reverb)
        audioEngine.attach(gainNode)
        reverb.loadFactoryPreset(.mediumChamber)
        applyReverb()

        // nil format lets the engine negotiate; a forced format can bypass the mixer.
        audioEngine.connect(unit, to: reverb, format: nil)
        audioEngine.connect(reverb, to: gainNode, format: nil)
        audioEngine.connect(gainNode, to: audioEngine.mainMixerNode, format: nil)
        applyVolume()

        do {
            audioEngine.prepare()
            try audioEngine.start()
            synthReady = true
            engineLabel = "DLS Synth"
        } catch {
            engineLabel = "No synth"
            errorMessage = error.localizedDescription
        }
    }

    private func ensureEngineRunning() {
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyVolume() {
        let amp = Float(max(0, min(1, volume)))
        // Cube-ish perceptual curve so the slider isn’t stuck in the “loud” half.
        let gain = amp * amp
        gainNode.outputVolume = gain
        audioEngine.mainMixerNode.outputVolume = gain

        guard let au = synthAU else { return }
        let cc = UInt32((amp * 127).rounded())
        for channel in 0..<16 {
            let status: UInt32 = 0xB0 | UInt32(channel)
            MusicDeviceMIDIEvent(au, status, 7, cc, 0)   // CC7 channel volume
            MusicDeviceMIDIEvent(au, status, 11, 127, 0) // CC11 expression
            AudioUnitSetParameter(
                au,
                AudioUnitParameterID(kAUGroupParameterID_Volume),
                AudioUnitScope(kAudioUnitScope_Group),
                AudioUnitElement(channel),
                AudioUnitParameterValue(cc),
                0
            )
        }

        // Universal Real Time SysEx master volume.
        let msb = UInt8(cc)
        let sysex: [UInt8] = [0xF0, 0x7F, 0x7F, 0x04, 0x01, 0x00, msb, 0xF7]
        sysex.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            MusicDeviceSysEx(au, base, UInt32(buf.count))
        }
    }

    private func applyReverb() {
        reverb.wetDryMix = reverbEnabled ? 22 : 0
    }

    private func resyncClock() {
        guard isPlaying else { return }
        clockTime = currentTime
        clockAnchor = Date()
    }

    private func scaledVelocity(_ velocity: UInt8) -> UInt32 {
        let amp = max(0, min(1, volume))
        if amp <= 0.001 { return 0 }
        return UInt32(max(1, min(127, (Double(velocity) * amp).rounded())))
    }

    // MARK: - Note dispatch

    private func resolvedProgram(for note: MIDINote) -> UInt8 {
        instrumentOverride ?? note.program
    }

    private func applyInstrumentOverride() {
        lastProgram.removeAll()
        sendPrograms()
    }

    private func sendPrograms() {
        guard let song, let au = synthAU else { return }
        var sent = Set<UInt8>()
        for note in song.notes {
            if sent.insert(note.channel).inserted {
                let program = resolvedProgram(for: note)
                MusicDeviceMIDIEvent(au, 0xC0 | UInt32(note.channel), UInt32(program), 0, 0)
                lastProgram[note.channel] = program
            }
        }
    }

    private func startHeldNotes(at time: TimeInterval) {
        guard let song else { return }
        for note in song.notes where note.start <= time && time < note.end {
            startNote(note)
        }
    }

    private func startNote(_ note: MIDINote) {
        guard let au = synthAU else { return }
        let program = resolvedProgram(for: note)
        if lastProgram[note.channel] != program {
            MusicDeviceMIDIEvent(au, 0xC0 | UInt32(note.channel), UInt32(program), 0, 0)
            lastProgram[note.channel] = program
        }
        let vel = scaledVelocity(note.velocity)
        if vel == 0 { return }
        MusicDeviceMIDIEvent(au, 0x90 | UInt32(note.channel), UInt32(note.pitch), vel, 0)
        sounding.insert(note.id)
    }

    private func stopNote(_ note: MIDINote) {
        guard let au = synthAU else { return }
        MusicDeviceMIDIEvent(au, 0x80 | UInt32(note.channel), UInt32(note.pitch), 0, 0)
        sounding.remove(note.id)
    }

    private func allSoundOff() {
        guard let au = synthAU else { return }
        for channel in 0..<16 {
            let status: UInt32 = 0xB0 | UInt32(channel)
            MusicDeviceMIDIEvent(au, status, 123, 0, 0) // all notes off
            MusicDeviceMIDIEvent(au, status, 120, 0, 0) // all sound off
        }
    }

    private func dispatchNotes(from t0: TimeInterval, to t1: TimeInterval) {
        guard let song else { return }
        if t1 < t0 {
            allSoundOff()
            sounding.removeAll()
            startHeldNotes(at: t1)
            return
        }
        for note in song.notes {
            if note.start > t0 && note.start <= t1 {
                startNote(note)
            }
            if note.end > t0 && note.end <= t1 {
                stopNote(note)
            }
        }
    }

    // MARK: - Clock

    private func startTick() {
        stopTick()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncPosition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTick() {
        tick?.invalidate()
        tick = nil
    }

    private func syncPosition() {
        guard !seeking, isPlaying, song != nil else { return }

        let now: TimeInterval
        if let clockAnchor {
            now = clockTime + Date().timeIntervalSince(clockAnchor) * TimeInterval(max(0.25, min(2.0, rate)))
        } else {
            now = currentTime
        }

        if looping, duration > 0, now >= duration {
            allSoundOff()
            sounding.removeAll()
            currentTime = 0
            lastDispatchTime = 0
            clockTime = 0
            clockAnchor = Date()
            applyVolume()
            sendPrograms()
            startHeldNotes(at: 0)
            return
        }

        if now >= duration {
            playerDidFinish()
            return
        }

        dispatchNotes(from: lastDispatchTime, to: now)
        lastDispatchTime = now
        currentTime = now
    }

    private func playerDidFinish() {
        guard !finishing else { return }
        finishing = true
        isPlaying = false
        clockAnchor = nil
        allSoundOff()
        sounding.removeAll()
        stopTick()
        currentTime = 0
        lastDispatchTime = 0
        finishing = false
    }

    private func remember(_ url: URL) {
        if MIDILibrary.isBundled(url) { return }
        var next = recents.filter { $0.path != url.path }
        next.insert(RecentFile(path: url.path, name: url.deletingPathExtension().lastPathComponent), at: 0)
        if next.count > 12 { next = Array(next.prefix(12)) }
        recents = next
        RecentFile.save(next)
    }
}

struct BundledPiece: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let fileName: String
}

struct RecentFile: Identifiable, Hashable, Codable {
    var id: String { path }
    let path: String
    let name: String

    var url: URL { URL(fileURLWithPath: path) }

    static func load() -> [RecentFile] {
        guard let data = UserDefaults.standard.data(forKey: "PianolaRecents") else { return [] }
        return (try? JSONDecoder().decode([RecentFile].self, from: data)) ?? []
    }

    static func save(_ items: [RecentFile]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "PianolaRecents")
        }
    }
}

enum MIDILibrary {
    static func url(named name: String) -> URL? {
        let file = name.hasSuffix(".mid") ? name : "\(name).mid"
        let fm = FileManager.default
        var candidates: [URL] = []

        if let root = Bundle.main.resourceURL {
            candidates.append(root.appendingPathComponent("MIDI").appendingPathComponent(file))
            candidates.append(root.appendingPathComponent(file))
            candidates.append(root.appendingPathComponent("Pianola_Pianola.bundle").appendingPathComponent(file))
            candidates.append(
                root.appendingPathComponent("Pianola_Pianola.bundle")
                    .appendingPathComponent("MIDI")
                    .appendingPathComponent(file)
            )
            candidates.append(
                root.appendingPathComponent("Pianola_Pianola.bundle")
                    .appendingPathComponent("Contents/Resources/MIDI")
                    .appendingPathComponent(file)
            )
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("Sources/Pianola/Resources/MIDI").appendingPathComponent(file))
        candidates.append(
            cwd.appendingPathComponent("Apps-fun and interesting/Pianola/Sources/Pianola/Resources/MIDI")
                .appendingPathComponent(file)
        )

        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    static func isBundled(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        return Self.url(named: name)?.standardizedFileURL == url.standardizedFileURL
            || ["Generated Scale", "C major scale"].contains(name)
    }
}
