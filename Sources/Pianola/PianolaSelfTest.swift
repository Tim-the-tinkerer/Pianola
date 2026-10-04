import Foundation

/// Checks that a Melograph Theremin file stays Theremin under As written.
/// Run with `--self-test`.
enum PianolaSelfTest {
    static func run() -> Int32 {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures.append(message)
                print("FAIL \(message)")
            }
        }

        expect(
            GMInstruments.isWrittenTheremin(trackName: "Melody (Theremin)", instrumentName: ""),
            "track title marks theremin"
        )
        expect(
            GMInstruments.isWrittenTheremin(trackName: "Melody", instrumentName: "Theremin"),
            "instrument name marks theremin"
        )
        expect(
            !GMInstruments.isWrittenTheremin(trackName: "Ocarina", instrumentName: ""),
            "ocarina is not theremin"
        )

        do {
            let named = try MIDIFile.parse(data: smf(format: 0, tracks: [
                musical(name: "Melody (Theremin)", instrument: nil, program: 79, pitch: 69),
            ]))
            expect(named.tracks.map(\.name) == ["Theremin"], "suffix lane \(named.tracks.map(\.name))")
            expect(named.notes.count == 1 && named.notes[0].program == GMInstruments.theremin, "suffix note program")

            let meta = try MIDIFile.parse(data: smf(format: 0, tracks: [
                musical(name: "Melody", instrument: "Theremin", program: 79, pitch: 69),
            ]))
            expect(meta.tracks.map(\.name) == ["Theremin"], "meta lane \(meta.tracks.map(\.name))")
            expect(meta.notes.allSatisfy { $0.program == GMInstruments.theremin }, "meta note program")

            let ocarina = try MIDIFile.parse(data: smf(format: 0, tracks: [
                musical(name: "Ocarina", instrument: nil, program: 79, pitch: 72),
            ]))
            expect(ocarina.tracks.map(\.name) == ["Ocarina"], "ocarina lane \(ocarina.tracks.map(\.name))")
            expect(ocarina.notes.allSatisfy { $0.program == 79 }, "ocarina stays program 79")

            let split = try MIDIFile.parse(data: smf(format: 1, tracks: [
                musical(name: "Bass", instrument: nil, program: 32, pitch: 40),
                musical(name: "Melody (Theremin)", instrument: "Theremin", program: 79, pitch: 67),
            ]))
            expect(
                Set(split.tracks.map(\.name)) == Set(["Acoustic Bass", "Theremin"]),
                "split lanes \(split.tracks.map(\.name))"
            )
            let programs = Set(split.notes.map(\.program))
            expect(programs == Set([32, GMInstruments.theremin]), "split programs \(programs)")
        } catch {
            failures.append("threw \(error)")
            print("FAIL threw \(error)")
        }

        if failures.isEmpty {
            print("Pianola self-test passed")
            return 0
        }
        print("Pianola self-test failed (\(failures.count))")
        return 1
    }

    private static func smf(format: UInt16, tracks: [Data]) -> Data {
        var data = Data()
        data.append(contentsOf: Array("MThd".utf8))
        appendU32(6, to: &data)
        appendU16(format, to: &data)
        appendU16(UInt16(tracks.count), to: &data)
        appendU16(480, to: &data)
        for track in tracks {
            data.append(contentsOf: Array("MTrk".utf8))
            appendU32(UInt32(track.count), to: &data)
            data.append(track)
        }
        return data
    }

    private static func musical(name: String?, instrument: String?, program: UInt8, pitch: UInt8) -> Data {
        var bytes: [UInt8] = [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]
        if let name { bytes += meta(0x03, name) }
        if let instrument { bytes += meta(0x04, instrument) }
        bytes += [0x00, 0xC0, program, 0x00, 0x90, pitch, 100, 0x81, 0x70, 0x80, pitch, 0x00, 0x00, 0xFF, 0x2F, 0x00]
        return Data(bytes)
    }

    private static func meta(_ type: UInt8, _ text: String) -> [UInt8] {
        let payload = Array(text.utf8)
        return [0x00, 0xFF, type, UInt8(payload.count)] + payload
    }

    private static func appendU16(_ value: UInt16, to data: inout Data) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    private static func appendU32(_ value: UInt32, to data: inout Data) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
}
