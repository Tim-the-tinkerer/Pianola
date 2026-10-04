# Changelog

All notable changes to **Pianola** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-10-03

### Added

- **As written** recognizes Theremin. A track whose instrument name is Theremin, or whose title ends in `(Theremin)`, stays Theremin instead of becoming Ocarina, and plays with the Theremin voice.

## [1.2.0] - 2026-08-25

### Changed

- Tracks that share a General MIDI program are **concatenated** into one lane (Glyphone multipart files no longer spawn a chip per data slice)
- Status line and chips show compact note counts

## [1.1.0] - 2026-08-25

### Added

- **Instrument** menu with the same General MIDI list as Glyphone (favorites on top, all 128 patches below)
- **As written** keeps each track’s program from the file; any other pick overrides every channel
- `.gitignore` for SwiftPM build products and the assembled `.app`

## [1.0.0] - 2026-08-25

### Added

- Initial macOS app: **MIDI file player** with General MIDI playback
- Bundled studies: **Generated Scale** and **C major scale**
- Live **piano roll** (click to seek) and **keyboard** that lights sounding notes
- Transport: play / pause / stop, skip ±5s, loop, seek slider
- Tempo (0.25×–2×), volume, optional chamber reverb
- Track chips with GM instrument names
- Open MIDI via File menu, drag-and-drop, or Finder double-click
- Keyboard preview on the on-screen keys (DLS synth)
- Recent files list
- App icon, SwiftPM package, `build-app.sh` release packaging
