# Third-party notices

Mac Mic Mixer source is licensed under GPL-3.0. The source archive shipped beside
the installer includes this project and the pinned upstream sources.

## OBS Studio

- Source: https://github.com/obsproject/obs-studio
- Version: 33.0.1, commit `65c320b46e1af5c7a555161aea6182cdf7a8c524`
- License: GNU GPL version 2 or later; see `third_party/obs-studio/COPYING` and README.
- Used: libobs, Metal renderer, macOS microphone input and device enumeration.
- The microphone source files are compiled unchanged into a small module that
  registers audio inputs only. The OBS application UI is not redistributed.
- libobs' upstream dependencies are resolved by its pinned CMake preset. Their
  licenses are copied from the dependency archive when available. Preserve all
  relevant upstream notices when preparing a distributed build.

## BlackHole

- Source: https://github.com/ExistentialAudio/BlackHole
- Version: v0.7.1, commit `e2b22aaaba4e507a097131704bf96dabc004d9cf`
- Source license: GNU GPL version 3; see `third_party/BlackHole/LICENSE`.
- The driver is built from the original C source with a separate configuration
  header defining Mac Mic Mixer names, identifiers and input/output visibility.
- Official BlackHole installers, icons and branding are not used. The custom
  driver has its own Info.plist and icon generated from this project's code.

For non-GPL distribution, consult the applicable upstream licensing terms before
shipping. The BlackHole README describes its alternative licensing channel.
