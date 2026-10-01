# vidioi development stages

## 0.1 — Current code
Native local editor, layer transforms, keyframes, Arabic text, SRT/fonts, color controls, AVFoundation exporter and optional AI edit-plan gateway. Validate compilation and export on macOS/iPhone before distribution.

## 0.2 — Editing reliability
Simulator/device smoke tests with portrait and landscape clips, transparent PNG, Arabic text and audio; image-only export, 4K stress tests, source duration-aware trimming UI, grouped undo, portable project archives, cancellation/progress, proxies, thumbnails and waveforms.

## 0.3 — Captions and sound
On-device speech recognition where available, optional server transcription, word timing editor, per-word color/highlight runs, loudness normalization, audio fades and ducking.

## 0.4 — Motion and masking
Vision subject/person segmentation, reusable alpha masks, tracking, layer parenting, cubic Bezier editor, SVG rasterization, templates with parameters, transition overlaps.

## 0.5 — Extensibility
Versioned asset packs and declarative effect manifests with explicit supported primitives. No unrestricted downloaded executable plugins on iOS. Color curves/3D LUTs, gesture editing, reusable preset library, and cancellable render queue.

## AI bridge
The first integration reviews metadata and edits only supported properties. Later integrations need explicit endpoints for transcription, frame analysis and generation, with clear data transfer controls and budget limits. Linking to a ChatGPT conversation requires a separate integration; it is not present in this version.
