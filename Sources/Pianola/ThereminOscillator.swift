import AVFoundation
import Foundation

/// Soft polyphonic theremin. Notes start on pitch, vibrato is centered,
/// and overlapping voices are rounded off instead of clipped.
/// The render callback and the note methods share one lock.
final class ThereminOscillator: @unchecked Sendable {
    private struct Voice {
        var noteID: Int
        var pitch: UInt8
        var gain: Float
        var phase: Double
        var frequency: Double
        var target: Double
        var envelope: Float
        var lowpass: Double
        var releasing: Bool
    }

    private let lock = NSLock()
    private var voices: [Voice] = []
    private var sampleRate: Double = 48_000
    private var vibratoPhase: Double = 0
    private var renderedSamples: Double = 0
    private var carryFrequency: Double = 0
    private var carrySample: Double = -1
    private var scratch: [Float] = []

    private static let maxVoices = 16
    private static let vibratoHertz = 5.2
    private static let vibratoCents = 12.0
    private static let glideSeconds = 0.055
    private static let attackSeconds = 0.040
    private static let releaseSeconds = 0.220
    private static let peakGain: Float = 0.16

    func setSampleRate(_ rate: Double) {
        guard rate > 0 else { return }
        lock.lock()
        sampleRate = rate
        lock.unlock()
    }

    func noteOn(pitch: UInt8, velocity: UInt8, noteID: Int) {
        lock.lock()
        defer { lock.unlock() }
        voices.removeAll { $0.noteID == noteID }
        if voices.count >= Self.maxVoices {
            if let quiet = voices.enumerated().filter(\.element.releasing).min(by: { $0.element.envelope < $1.element.envelope })?.offset {
                voices.remove(at: quiet)
            } else {
                voices.removeFirst()
            }
        }
        let target = Self.frequency(for: pitch)
        let legato = carrySample >= 0 && renderedSamples - carrySample < sampleRate * 0.20 && carryFrequency > 20
        voices.append(
            Voice(
                noteID: noteID,
                pitch: pitch,
                gain: Self.peakGain * Float(max(1, velocity)) / 127,
                phase: 0,
                frequency: legato ? carryFrequency : target,
                target: target,
                envelope: 0,
                lowpass: 0,
                releasing: false
            )
        )
    }

    func noteOff(noteID: Int) {
        lock.lock()
        for index in voices.indices where voices[index].noteID == noteID {
            voices[index].releasing = true
        }
        lock.unlock()
    }

    func allOff() {
        lock.lock()
        voices.removeAll()
        lock.unlock()
    }

    func renderForTest(frames: Int, sampleRate: Double) -> [Float] {
        setSampleRate(sampleRate)
        var output = [Float](repeating: 0, count: frames)
        output.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = renderLocked(into: base, frames: frames)
        }
        return output
    }

    func makeNode() -> AVAudioSourceNode {
        let oscillator = self
        return AVAudioSourceNode { isSilence, _, frameCount, audioBufferList in
            let voiced = oscillator.render(frameCount: frameCount, audioBufferList: audioBufferList)
            isSilence.pointee = ObjCBool(!voiced)
            return noErr
        }
    }

    private func render(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let frames = Int(frameCount)
        guard frames > 0, buffers.count > 0, buffers[0].mData != nil else { return false }
        if scratch.count < frames {
            scratch = [Float](repeating: 0, count: frames)
        }
        let voiced = scratch.withUnsafeMutableBufferPointer { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return renderLocked(into: base, frames: frames)
        }
        let channelsInFirst = max(1, Int(buffers[0].mNumberChannels))
        if buffers.count == 1 && channelsInFirst > 1 {
            writeInterleaved(buffers: buffers, frames: frames, channels: channelsInFirst)
        } else {
            writePlanar(buffers: buffers, frames: frames)
        }
        return voiced
    }

    private func writePlanar(buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        let byteCount = frames * MemoryLayout<Float>.size
        guard let destination = buffers[0].mData else { return }
        scratch.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            destination.copyMemory(from: base, byteCount: byteCount)
        }
        for index in 0..<buffers.count {
            var buffer = buffers[index]
            if index > 0, let data = buffer.mData, let source = buffers[0].mData {
                data.copyMemory(from: source, byteCount: byteCount)
            }
            buffer.mDataByteSize = UInt32(byteCount)
            buffers[index] = buffer
        }
    }

    private func writeInterleaved(buffers: UnsafeMutableAudioBufferListPointer, frames: Int, channels: Int) {
        guard let data = buffers[0].mData else { return }
        let destination = data.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            let sample = scratch[frame]
            let base = frame * channels
            for channel in 0..<channels {
                destination[base + channel] = sample
            }
        }
        var buffer = buffers[0]
        buffer.mDataByteSize = UInt32(frames * channels * MemoryLayout<Float>.size)
        buffers[0] = buffer
    }

    private func renderLocked(into samples: UnsafeMutablePointer<Float>, frames: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard sampleRate > 0 else {
            samples.update(repeating: 0, count: frames)
            return false
        }

        let vibratoStep = 2 * Double.pi * Self.vibratoHertz / sampleRate
        let glide = 1 - exp(-1 / (Self.glideSeconds * sampleRate))
        let attack = Float(1 / (Self.attackSeconds * sampleRate))
        let release = Float(1 / (Self.releaseSeconds * sampleRate))
        var voiced = false

        for frame in 0..<frames {
            vibratoPhase += vibratoStep
            if vibratoPhase > 2 * Double.pi {
                vibratoPhase -= 2 * Double.pi
            }
            let lfo = sin(vibratoPhase)
            let bend = pow(2.0, lfo * Self.vibratoCents / 1200.0)
            let tremolo = 1 + 0.05 * lfo
            var mix = 0.0
            var index = 0
            while index < voices.count {
                var voice = voices[index]
                voice.frequency += (voice.target - voice.frequency) * glide
                voice.phase += 2 * Double.pi * voice.frequency * bend / sampleRate
                if voice.phase > 2 * Double.pi {
                    voice.phase.formTruncatingRemainder(dividingBy: 2 * Double.pi)
                }
                if voice.releasing {
                    voice.envelope = max(0, voice.envelope - release)
                } else {
                    voice.envelope = min(1, voice.envelope + attack)
                }
                let raw = sin(voice.phase) + 0.10 * sin(2 * voice.phase) + 0.025 * sin(3 * voice.phase)
                let cutoff = min(4800.0, max(1800.0, voice.frequency * 5))
                let lowpass = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
                voice.lowpass += (raw - voice.lowpass) * lowpass
                mix += voice.lowpass * Double(voice.envelope * voice.gain) * tremolo
                if voice.releasing && voice.envelope <= 0 {
                    voices.remove(at: index)
                } else {
                    voices[index] = voice
                    index += 1
                }
            }
            // tanh rounds a chord off. A hard clip at ±1 was the buzz.
            let sample = Float(tanh(mix))
            samples[frame] = sample
            if sample != 0 { voiced = true }
        }

        if let lead = voices.max(by: { $0.envelope < $1.envelope }) {
            carryFrequency = lead.frequency
            carrySample = renderedSamples + Double(frames)
        }
        renderedSamples += Double(frames)
        return voiced
    }

    private static func frequency(for pitch: UInt8) -> Double {
        440.0 * pow(2.0, (Double(pitch) - 69.0) / 12.0)
    }
}

private extension UnsafeMutablePointer where Pointee == Float {
    func update(repeating value: Float, count: Int) {
        for index in 0..<count {
            self[index] = value
        }
    }
}
