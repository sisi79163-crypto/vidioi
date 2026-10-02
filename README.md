# vidioi

Native iPhone/iPad video editor with Arabic typography, layered media, keyframe animation, and an optional OpenAI editing assistant. This is a first implementation (0.1.0), not a finished DaVinci-equivalent product.

## Implemented

- Local projects with atomic JSON saves, project library, 50-step undo/redo.
- Import video, audio, images/transparent PNG, TTF/OTF fonts, SRT captions, and JSON edit plans from Files.
- Sequential video import; up to 32 visual/audio lanes and overlapping layers.
- Source trims, timeline position, duration, speed 0.25–4×, volume, split and duplicate.
- Arabic/multiline text, fonts, red/gold/white/mint color presets, editable font size.
- Position, scale, horizontal stretch, rotation, opacity; eased keyframes and fade/pop/slide entrance presets.
- Brightness, contrast, saturation for video and images.
- Shared custom AVFoundation/Core Image compositor for preview and MP4 export. 9:16, 16:9, square and 2160×3840 export settings; 24/25/30/60 FPS.
- AI assistant prepares a bounded JSON edit plan. Preview the plan before applying; undo it afterward.
- Server-side OpenAI key, device Keychain gateway token, authenticated requests, request limits, schema/semantic validation, no source-media upload.

## Current verification status

GitHub Actions successfully built the arm64 iOS application on 2026-10-02. All 9 Swift core tests and 11 gateway tests passed. The unsigned IPA was packaged and uploaded in [build run 36943710049](https://github.com/sisi79163-crypto/vidioi/actions/runs/36943710049), from source commit `3f7527f9ce314c924c698f4c8e555ab301954bda`.

The native app has not been launched or export-tested on a physical iPhone or simulator yet. The build uses Swift 5 language mode and reports Swift 6 sendability migration warnings in the custom compositor; these do not fail this build.

An API key and deployed HTTPS gateway are not configured. Real AI requests have not been tested. The app works as a local editor without an AI connection; imported JSON plans provide an offline assistant bridge.

## Build on GitHub

1. Create a repository named `vidioi` with branch `main`, then upload this folder's contents, including `.github/workflows/build-ios.yml`.
2. Open **Actions → Build vidioi IPA**. A push to `main` triggers the workflow; it can also be run manually.
3. Once tests and the native build succeed, download **vidioi-unsigned-ipa** from the run's artifacts. The archive contains `vidioi-unsigned.ipa`.
4. Sign and install the IPA using SideStore or an Apple development signing workflow. The produced IPA is unsigned, not directly installable. SideStore/device pairing and signing are external steps.

No paid third-party editing SDK or XcodeGen is required. GitHub runner availability and account build minutes depend on the account.

## Build on a Mac

```sh
python3 scripts/generate_project.py
swift test
open vidioi.xcodeproj
```

Select a signing team and your device in Xcode. Deployment target: iOS 17. Project files are also included and can be opened without generating again.

## Connect the AI assistant

The connection uses OpenAI's Responses API; it does not attach this ChatGPT session or reuse its subscription. Set up API billing separately. Only the prompt and project metadata/text are sent; the assistant cannot hear source clips or transcribe them through this endpoint.

```sh
cd Server
cp .env.example .env
```

Fill `OPENAI_API_KEY`, `OPENAI_MODEL`, and a random `VIDIOI_TOKEN` of at least 16 characters. Never commit `.env` or place the OpenAI key in the IPA. Then:

```sh
npm test
npm start
```

Deploy the gateway behind HTTPS (the Dockerfile is included). In the app's settings, enter the HTTPS base URL and the gateway token. The app appends `/v1/edit`. No gateway has been deployed with this deliverable.

The gateway returns a reviewable edit plan and cannot execute code, access local files, or download arbitrary URLs. It rejects unknown clip IDs, bad keyframes, paths and values. The current token model is for a personal app, not a public multiuser service.

Example request: “اجعل النص الأول أحمر مع حركة pop، وأضف عبارة احفظ الفيديو في الثانية 20 لمدة ثانيتين”. Actual media duration bounds are additionally checked by the native render engine.

## Using your own assets

Import from Files. Files are copied into the project sandbox. Import fonts before selecting them. Import an SRT containing word-level timings to animate each timed word; this version does not automatically derive word timing from speech. Use a separate text layer for highlighted red words. Project assets are also accessible through iOS Files app under vidioi when file sharing is available.

Sharing `project.json` shares metadata only. It is not a portable full-media project archive. Keep the project folder and its `Assets` directory together for backups. Importing JSON through the app currently imports edit plans, not complete projects.

## Limits and next development work

- No subject segmentation/masking, tracking, automatic transcription, audio cleanup, 3D LUT importer, arbitrary effect plugins, nested compositions or automatic scene detection yet.
- No video generation, stock asset downloads, full DaVinci color tools or Fusion node editor.
- No transition overlap controls; media cuts are hard cuts. Motion presets apply to layer opacity/position/scale.
- Fonts and other imported files are copied; failed batch imports can leave unused asset files until the project folder is cleaned. There is no asset garbage collection or project delete UI yet.
- Sliders produce individual undo steps. Frame caches/proxies, drag trimming, thumbnail/waveform generation and optimized 4K memory use remain development work.
- HDR input is currently rendered to SDR; variable-frame-rate and unsupported codecs must be tested on device. Source-audio pitch preservation is not implemented for speed changes.
- Device performance limits 4K and overlapping tracks. Image-only/title-only/audio-only compositions require particular on-device smoke testing.

## Source layout

`Core/` — project codec, interpolation, subtitle parser, atomic edit plans.

`Engine/` — composition builder, media timing/audio mix, custom frame renderer, exporter.

`App/` — SwiftUI editor, timeline, inspector, motion, project storage, Keychain and assistant UI.

`Server/` — dependency-free Node gateway, Responses integration, validation and tests.

`Tests/` — Swift core tests; `scripts/` — deterministic Xcode generation; `.github/workflows/` — macOS build/IPA packaging.

## References

- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Apple AVVideoCompositing](https://developer.apple.com/documentation/avfoundation/avvideocompositing)
- [GitHub workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts)
