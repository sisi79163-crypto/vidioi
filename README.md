# vidioi 0.2

Native iPhone/iPad video editing with a redesigned dark studio, a layered timeline, Arabic titles, motion controls and a ChatGPT editing assistant.

## What changed in 0.2

- New charcoal/lime design system, studio dashboard, project cover images, empty state and updated app icon.
- Large clean AVPlayer canvas without overlapping player controls. Contextual tool sheets keep the editor uncluttered.
- Timeline scrubbing, zoom, moving clips and edge trimming. Clip thumbnails use real imported media.
- Arabic title presets, color controls, motion previews and keyframe editing.
- Import media from Photos as well as Files. Imported assets remain local.
- Dedicated export sheet for 1080p/4K, frame rate, progress state and sharing.
- **Continue with ChatGPT** using OpenAI's documented public-client dynamic registration flow: PKCE, state/nonce, a loopback callback, RSA signature validation and Keychain storage.
- Model picker populated from the signed-in account; streamed Responses requests must reach a completed event before any edit plan can be applied.
- Optional self-hosted OpenAI API gateway remains available, with an authenticated status test.

## Connect ChatGPT

Open the profile button in the studio or **AI → اتصال** in the editor. Select ChatGPT, press **Continue with ChatGPT**, then complete OpenAI's sign-in and consent screen. The app requests permission to use eligible ChatGPT plan usage and retrieves the models available to the account. Select a model and request an edit.

This uses the documented preview flow for open-source clients. Availability is controlled by OpenAI and the user's account/workspace. The app has no access to prior ChatGPT conversations. No API key is embedded in the application. Successful live account consent and inference still require testing on the user's device; compilation and contract tests alone do not prove account eligibility or native loopback callback support in every iOS environment.

For an existing API deployment, choose **خادم API**, enter the HTTPS gateway base URL and its app token, then test the connection. Keep `OPENAI_API_KEY` on that server. `Server/.env.example` and `Server/Dockerfile` are included. The status test verifies authentication/configuration, not a billed inference request. No API gateway is deployed by this repository.

## Edit with the assistant

The assistant receives the instruction and project metadata/text, not source video or audio. It proposes only supported timeline operations. Review the plan, apply it, or reject it; applied changes can be undone. Request generation is cancellable, and changing the project before a response arrives invalidates that response. The assistant does not automatically transcribe speech or generate video.

Examples:

- “اجعل أول عنوان أحمر مع حركة Pop، ولا تغيّر الكلمات.”
- “خفّض تشبع الفيديو وزد التباين قليلًا.”
- “أضف عبارة احفظ الفيديو في الثانية 20 لمدة ثانيتين.”

## Build

GitHub Actions runs the Node gateway tests, Swift model/OAuth/stream contract tests, an iOS device build, a simulator build and UI/export smoke checks. Artifacts include the unsigned IPA and actual simulator screenshots. Use the latest successful run under [Actions](https://github.com/sisi79163-crypto/vidioi/actions).

On a Mac:

```sh
python3 scripts/generate_project.py
swift test
open vidioi.xcodeproj
```

Target: iOS 17+. Bundle ID: `com.mostafa.vidioi`. Sign using Xcode or SideStore; the CI IPA is unsigned. Native smoke tests use `--screenshot-editor`, `--screenshot-motion`, `--screenshot-ai` and `--render-smoke` launch arguments; normal use does not create the generated test project.

## Editing capabilities and current limits

Supported: up to 32 lanes, clips with independent source/timeline trims, 0.25–4× speed, audio volume, split/duplicate, opacity/position/scale/stretch/rotation keyframes, Arabic/multiline text, imported fonts and SRT, brightness/contrast/saturation, and MP4 export. Projects autosave with undo/redo history during the session.

Not implemented: subject segmentation, object tracking, automatic transcription, 3D LUTs, arbitrary executable plugins, nested timelines, advanced audio mastering or generated media. 4K and large projects still need real-device performance testing. Imported JSON files are edit plans; exporting project metadata alone does not include source media. The app is an evolving editor, not feature-equivalent to DaVinci Resolve.

## Security and verification

- OAuth tokens are stored as one atomic Keychain record. No credentials are committed or logged.
- Callback checks bind state, issued client ID, exact loopback path and port. ID-token validation checks RSA signature, issuer, audience, expiry, subject and nonce.
- Account renewal cannot overwrite a signed-out/switched account. No private ChatGPT backend endpoints are used.
- Authentication and inference tests use local cryptographic fixtures and simulated events; they do not authenticate a real user.
- The gateway authenticates every edit/status request, bounds body size/rate and validates all edit commands.

## References

- [OpenAI registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Apple AVVideoCompositing](https://developer.apple.com/documentation/avfoundation/avvideocompositing)
