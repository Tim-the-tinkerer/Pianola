import Foundation

struct MIDINote: Identifiable, Equatable {
    let id: Int
    let pitch: UInt8
    let velocity: UInt8
    let channel: UInt8
    let track: Int
    let startTick: Int
    let endTick: Int
    let start: TimeInterval
    let end: TimeInterval
    let program: UInt8

    var duration: TimeInterval { max(0, end - start) }

    var pitchName: String { MIDIFile.noteName(pitch) }
}

struct MIDITrackInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let program: UInt8?
    let channel: UInt8?
    let noteCount: Int
}

struct MIDISong: Equatable {
    var title: String
    var ticksPerQuarter: Int
    var format: Int
    var tempoBPM: Double
    var numerator: Int
    var denominator: Int
    var keySignature: String
    var duration: TimeInterval
    var notes: [MIDINote]
    var tracks: [MIDITrackInfo]
    var pitchMin: UInt8
    var pitchMax: UInt8
    var beatDuration: TimeInterval
    var sourceURL: URL?

    var timeSignatureLabel: String { "\(numerator)/\(denominator)" }

    var noteCount: Int { notes.count }

    func notesActive(at time: TimeInterval) -> [MIDINote] {
        guard !notes.isEmpty else { return [] }
        var lo = 0
        var hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].start <= time { lo = mid + 1 } else { hi = mid }
        }
        var result: [MIDINote] = []
        var i = lo - 1
        while i >= 0 {
            let note = notes[i]
            if note.end > time { result.append(note) }
            if time - note.start > 32 { break }
            i -= 1
        }
        return result
    }
}

enum MIDIParseError: Error, LocalizedError {
    case notMIDI
    case truncated
    case unsupportedDivision

    var errorDescription: String? {
        switch self {
        case .notMIDI: return "This is not a MIDI file."
        case .truncated: return "The MIDI file is incomplete."
        case .unsupportedDivision: return "SMPTE time division is not supported."
        }
    }
}

enum MIDIFile {
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static func noteName(_ pitch: UInt8) -> String {
        let n = Int(pitch)
        return "\(noteNames[n % 12])\(n / 12 - 1)"
    }

    static func isBlackKey(_ pitch: Int) -> Bool {
        switch pitch % 12 {
        case 1, 3, 6, 8, 10: return true
        default: return false
        }
    }

    static func parse(url: URL) throws -> MIDISong {
        let data = try Data(contentsOf: url)
        var song = try parse(data: data)
        song.sourceURL = url
        if song.title.isEmpty {
            song.title = url.deletingPathExtension().lastPathComponent
        }
        return song
    }

    static func parse(data: Data) throws -> MIDISong {
        var r = Reader(data: data)
        guard r.ascii(4) == "MThd" else { throw MIDIParseError.notMIDI }
        let headerLen = Int(r.u32())
        guard headerLen >= 6 else { throw MIDIParseError.truncated }
        let format = Int(r.u16())
        let trackCount = Int(r.u16())
        let divisionRaw = r.u16()
        if headerLen > 6 { r.skip(headerLen - 6) }

        guard divisionRaw & 0x8000 == 0 else { throw MIDIParseError.unsupportedDivision }
        let tpq = Int(divisionRaw)
        guard tpq > 0 else { throw MIDIParseError.truncated }

        var tempoEvents: [(tick: Int, usPerQuarter: Int)] = [(0, 500_000)]
        var numerator = 4
        var denominator = 4
        var keySignature = "C major"
        var title = ""
        var rawNotes: [RawNote] = []
        var tracks: [MIDITrackInfo] = []
        var thereminTracks = Set<Int>()
        var nextID = 0

        for trackIndex in 0..<trackCount {
            guard r.remaining >= 8 else { throw MIDIParseError.truncated }
            guard r.ascii(4) == "MTrk" else { throw MIDIParseError.badTrackFallback }
            let trackLen = Int(r.u32())
            guard r.remaining >= trackLen else { throw MIDIParseError.truncated }
            let trackEnd = r.offset + trackLen

            var tick = 0
            var running: UInt8 = 0
            var trackName = ""
            var instrumentName = ""
            var programForChannel = [UInt8](repeating: 0, count: 16)
            var firstProgram: UInt8?
            var firstChannel: UInt8?
            var noteCount = 0
            // (channel, pitch) -> stack of opens
            var open: [UInt16: [(tick: Int, vel: UInt8, program: UInt8, id: Int)]] = [:]

            while r.offset < trackEnd {
                let delta = r.vlq()
                tick += delta
                guard r.offset < trackEnd else { break }
                var status = r.peek()
                if status < 0x80 {
                    status = running
                } else {
                    _ = r.u8()
                    if status < 0xF0 {
                        running = status
                    }
                }

                if status == 0xFF {
                    let meta = r.u8()
                    let len = r.vlq()
                    let payload = r.bytes(len)
                    if meta == 0x2F {
                        break
                    } else if meta == 0x51, payload.count == 3 {
                        let us = (Int(payload[0]) << 16) | (Int(payload[1]) << 8) | Int(payload[2])
                        if us > 0 {
                            tempoEvents.append((tick, us))
                        }
                    } else if meta == 0x58, payload.count >= 2 {
                        numerator = Int(payload[0])
                        denominator = 1 << Int(payload[1])
                    } else if meta == 0x59, payload.count >= 2 {
                        keySignature = keyName(sf: Int8(bitPattern: payload[0]), minor: payload[1] == 1)
                    } else if meta == 0x03 || meta == 0x04 {
                        let name = String(bytes: payload, encoding: .utf8)
                            ?? String(bytes: payload, encoding: .isoLatin1)
                            ?? ""
                        if !name.isEmpty {
                            if meta == 0x04 {
                                instrumentName = name
                            } else {
                                trackName = name
                                if title.isEmpty { title = name }
                            }
                        }
                    }
                    continue
                }

                if status == 0xF0 || status == 0xF7 {
                    let len = r.vlq()
                    r.skip(len)
                    continue
                }

                let type = status & 0xF0
                let channel = status & 0x0F

                switch type {
                case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
                    let d1 = r.u8()
                    let d2 = r.u8()
                    if type == 0x90 || type == 0x80 {
                        let pitch = d1
                        let vel = d2
                        let key = UInt16(channel) << 8 | UInt16(pitch)
                        let isOn = type == 0x90 && vel > 0
                        if isOn {
                            if firstChannel == nil { firstChannel = channel }
                            let prog = programForChannel[Int(channel)]
                            var stack = open[key] ?? []
                            stack.append((tick, vel, prog, nextID))
                            nextID += 1
                            open[key] = stack
                            noteCount += 1
                        } else if var stack = open[key], !stack.isEmpty {
                            let started = stack.removeLast()
                            open[key] = stack
                            rawNotes.append(
                                RawNote(
                                    id: started.id,
                                    pitch: pitch,
                                    velocity: started.vel,
                                    channel: channel,
                                    track: trackIndex,
                                    startTick: started.tick,
                                    endTick: max(started.tick + 1, tick),
                                    program: started.program
                                )
                            )
                        }
                    }
                case 0xC0, 0xD0:
                    let d1 = r.u8()
                    if type == 0xC0 {
                        programForChannel[Int(channel)] = d1
                        if firstProgram == nil { firstProgram = d1 }
                        if firstChannel == nil { firstChannel = channel }
                    }
                default:
                    break
                }
            }

            r.offset = trackEnd

            for (key, stack) in open {
                let pitch = UInt8(key & 0xFF)
                let channel = UInt8(key >> 8)
                for started in stack {
                    rawNotes.append(
                        RawNote(
                            id: started.id,
                            pitch: pitch,
                            velocity: started.vel,
                            channel: channel,
                            track: trackIndex,
                            startTick: started.tick,
                            endTick: max(started.tick + 1, tick),
                            program: started.program
                        )
                    )
                }
            }

            if noteCount == 0 && trackName.isEmpty && firstProgram == nil {
                continue
            }

            let writtenTheremin = GMInstruments.isWrittenTheremin(
                trackName: trackName,
                instrumentName: instrumentName
            )
            if writtenTheremin {
                firstProgram = GMInstruments.theremin
                thereminTracks.insert(trackIndex)
            }

            let displayName: String
            if writtenTheremin {
                displayName = "Theremin"
            } else if !trackName.isEmpty {
                displayName = trackName
            } else if let firstProgram {
                displayName = GMInstruments.shortName(for: firstProgram)
            } else if noteCount > 0 {
                displayName = "Track \(trackIndex)"
            } else {
                continue
            }

            tracks.append(
                MIDITrackInfo(
                    id: trackIndex,
                    name: displayName,
                    program: firstProgram,
                    channel: firstChannel,
                    noteCount: noteCount
                )
            )
        }

        tempoEvents.sort { $0.tick < $1.tick }
        var compactTempo: [(tick: Int, usPerQuarter: Int)] = []
        for ev in tempoEvents {
            if let last = compactTempo.last, last.tick == ev.tick {
                compactTempo[compactTempo.count - 1] = ev
            } else {
                compactTempo.append(ev)
            }
        }

        func seconds(forTick tick: Int) -> TimeInterval {
            var t: TimeInterval = 0
            var i = 0
            while i < compactTempo.count {
                let startTick = compactTempo[i].tick
                let us = compactTempo[i].usPerQuarter
                let endTick = (i + 1 < compactTempo.count) ? compactTempo[i + 1].tick : tick
                let clipped = min(tick, endTick)
                if clipped > startTick {
                    t += TimeInterval(clipped - startTick) * TimeInterval(us) / 1_000_000.0 / TimeInterval(tpq)
                }
                if clipped == tick { break }
                i += 1
            }
            return t
        }

        let notes: [MIDINote] = rawNotes.map { raw in
            let program = thereminTracks.contains(raw.track) ? GMInstruments.theremin : raw.program
            return MIDINote(
                id: raw.id,
                pitch: raw.pitch,
                velocity: raw.velocity,
                channel: raw.channel,
                track: raw.track,
                startTick: raw.startTick,
                endTick: raw.endTick,
                start: seconds(forTick: raw.startTick),
                end: seconds(forTick: raw.endTick),
                program: program
            )
        }.sorted { a, b in
            if a.start == b.start { return a.pitch < b.pitch }
            return a.start < b.start
        }

        let (mergedTracks, mergedNotes) = concatenateTracks(tracks: tracks, notes: notes)

        let duration = mergedNotes.map(\.end).max() ?? 0
        let firstTempo = compactTempo.first?.usPerQuarter ?? 500_000
        let bpm = 60_000_000.0 / Double(max(1, firstTempo))
        let beatDuration = TimeInterval(firstTempo) / 1_000_000.0
        let pitchMin = mergedNotes.map(\.pitch).min() ?? 60
        let pitchMax = mergedNotes.map(\.pitch).max() ?? 72

        return MIDISong(
            title: title,
            ticksPerQuarter: tpq,
            format: format,
            tempoBPM: bpm,
            numerator: max(1, numerator),
            denominator: max(1, denominator),
            keySignature: keySignature,
            duration: duration,
            notes: mergedNotes,
            tracks: mergedTracks,
            pitchMin: pitchMin,
            pitchMax: pitchMax,
            beatDuration: beatDuration,
            sourceURL: nil
        )
    }

    /// Fold SMF tracks that share a GM program into one lane.
    /// Multipart files (Glyphone data 1/N … N/N) otherwise spawn a chip per slice.
    static func concatenateTracks(
        tracks: [MIDITrackInfo],
        notes: [MIDINote]
    ) -> (tracks: [MIDITrackInfo], notes: [MIDINote]) {
        let sounding = tracks.filter { $0.noteCount > 0 }
        guard !sounding.isEmpty else { return ([], notes) }

        var order: [UInt8] = []
        var counts: [UInt8: Int] = [:]
        var channels: [UInt8: UInt8] = [:]
        for track in sounding {
            let program = track.program ?? 0
            if !order.contains(program) { order.append(program) }
            counts[program, default: 0] += track.noteCount
            if channels[program] == nil, let ch = track.channel {
                channels[program] = ch
            }
        }

        let merged: [MIDITrackInfo] = order.enumerated().map { index, program in
            MIDITrackInfo(
                id: index,
                name: GMInstruments.shortName(for: program),
                program: program,
                channel: channels[program],
                noteCount: counts[program] ?? 0
            )
        }
        let idByProgram = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let remapped = notes.map { note in
            MIDINote(
                id: note.id,
                pitch: note.pitch,
                velocity: note.velocity,
                channel: note.channel,
                track: idByProgram[note.program] ?? 0,
                startTick: note.startTick,
                endTick: note.endTick,
                start: note.start,
                end: note.end,
                program: note.program
            )
        }
        return (merged, remapped)
    }

    private static func keyName(sf: Int8, minor: Bool) -> String {
        let majors = ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"]
        let minors = ["Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"]
        let idx = Int(sf) + 7
        guard idx >= 0, idx < 15 else { return minor ? "A minor" : "C major" }
        return minor ? "\(minors[idx]) minor" : "\(majors[idx]) major"
    }
}

private struct RawNote {
    let id: Int
    let pitch: UInt8
    let velocity: UInt8
    let channel: UInt8
    let track: Int
    let startTick: Int
    let endTick: Int
    let program: UInt8
}

private extension MIDIParseError {
    static var badTrackFallback: MIDIParseError { .truncated }
}

private struct Reader {
    let data: Data
    var offset: Int = 0

    var remaining: Int { data.count - offset }

    mutating func u8() -> UInt8 {
        guard offset < data.count else { return 0 }
        defer { offset += 1 }
        return data[offset]
    }

    func peek() -> UInt8 {
        guard offset < data.count else { return 0 }
        return data[offset]
    }

    mutating func u16() -> UInt16 {
        let hi = UInt16(u8())
        let lo = UInt16(u8())
        return (hi << 8) | lo
    }

    mutating func u32() -> UInt32 {
        let a = UInt32(u8())
        let b = UInt32(u8())
        let c = UInt32(u8())
        let d = UInt32(u8())
        return (a << 24) | (b << 16) | (c << 8) | d
    }

    mutating func ascii(_ n: Int) -> String {
        let bytes = bytes(n)
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    mutating func bytes(_ n: Int) -> [UInt8] {
        guard n > 0 else { return [] }
        let end = min(data.count, offset + n)
        let slice = Array(data[offset..<end])
        offset = end
        return slice
    }

    mutating func skip(_ n: Int) {
        offset = min(data.count, offset + n)
    }

    mutating func vlq() -> Int {
        var value = 0
        for _ in 0..<4 {
            let b = u8()
            value = (value << 7) | Int(b & 0x7F)
            if b & 0x80 == 0 { break }
        }
        return value
    }
}
