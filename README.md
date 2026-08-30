# Pianola

A native macOS **MIDI file player**. Open Standard MIDI files, hear them through the system General MIDI synth, and watch a live piano roll plus keyboard as notes play.

Two C major scale studies are bundled so it plays something the first time you open it.

## Features

- Play, pause, stop, seek, loop
- Tempo (0.25×–2×) and volume
- Optional chamber reverb
- **Instrument** override — same General MIDI menu as Glyphone (or leave **As written**)
- Piano roll with click-to-seek
- Keyboard that lights up with the sounding notes — click a key to preview
- Track list with General MIDI instrument names
- Open via **File → Open**, drag-and-drop, or double-click a `.mid` file
- Bundled pieces: **Generated Scale** and **C major scale**

## Build & run

```bash
./build-app.sh
```

Creates and opens `Pianola.app`. Use `--no-launch` to build only.

```bash
swift build -c release   # binary only → .build/release/Pianola
```

Requires macOS 13+, Xcode command-line tools.

## Usage

1. Launch Pianola — **Generated Scale** loads automatically.
2. Press **Play** (or Space).
3. Switch to **C major scale** in the library, or open any `.mid` / `.midi` file.
4. Drag the piano roll or the timeline to seek. Enable **Loop** to repeat.

Keyboard: **Space** play/pause · **⌘O** open · **⌘.** stop.

## Tech

SwiftUI + AppKit shell. MIDI is parsed locally for the roll and keyboard. Playback uses the macOS DLS General MIDI synth via `AVAudioEngine` + `AVAudioSequencer`, with `AVMIDIPlayer` as a fallback. SwiftPM package; same layout as Binaural / Sonora.
