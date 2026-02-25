# Post Enhancer 2.0 (Clipboard Refiner V2)

Native macOS SwiftUI app for refining text posts with cloud or local models, image context, and offline-safe caching.

## What Changed

- Full windowed macOS app UI (SwiftUI)
- Drag-and-drop image context (PNG/JPEG/HEIC/TIFF)
- Offline rewrite cache fallback
- macOS Share Sheet integration (`NSSharingServicePicker`)
- Prompt `Skills` bundle (in-app + Codex skill files)
- Local LLM support via on-device model paths

## Recent Performance Updates (2026-02)

- Stream UI delivery is coalesced (~30 FPS) to reduce view-update churn on long generations.
- Rewrite output hot-path overpublishing was reduced (`currentOutput` is no longer `@Published`).
- Cancel-handler dispatch is non-blocking (removed synchronous semaphore waits in cancellable handler path).
- Result panel height measurement is suppressed while streaming, and popover window sizing updates are debounced.
- Pasted image-path auto-detection adds cheap early guards before expensive diffing.
- Behavior settings reduce write/publish storms:
  - Aggressiveness commits on slider release (staged local draft while dragging)
  - System prompt editor commits are debounced (~300ms)

## Features

- Providers: OpenAI, Anthropic, xAI, Local
- Style presets: Proofread, Shorter, More formal, More casual, Less cringe, Enhance X post, Enhance AI prompt, Explain
- Prompt skill templates:
  - Thread Crafter
  - Launch Writer
  - Private Notes
  - Debug Brief
- Auto-copy result (optional)
- Local history export/clear
- API key storage in macOS Keychain (cloud providers)
- Saved local model folder paths (multiple models)

## Requirements

- macOS 15+
- Xcode (project currently uses Swift language mode `5.0`)
- API key for OpenAI/Anthropic/xAI (optional if using Local only)
- `python3` + [`mlx-lm`](https://github.com/ml-explore/mlx-examples/tree/main/llms) installed for Local provider runtime

## Run

1. Open `/Users/espenmac/Code/ClipboardRefinerV2/ClipboardRefiner.xcodeproj`
2. Build and run scheme `ClipboardRefiner`
3. In Settings, choose provider/model and set API key (if needed)
4. Drag text/images, run Enhance, then Share/Copy

## Performance Profiling

- Runtime perf telemetry is opt-in via `CLIPBOARD_REFINER_PERF=1`.
- Telemetry emits newline-delimited JSON records to stderr (`type=perf`) for:
  - Rewrite request latency (`rewrite.request`)
  - Provider stream volume/latency (`provider.stream`)
  - Attachment ingest (`attachments.load_file`, `attachments.prepare`)
  - Draft persistence (`menu_draft.persist`)
- Helper script:
  - `./scripts/perf-profile.sh 90` (builds Release, runs app with telemetry for 90s, writes JSONL path)

## Local Model Quick Start

1. Install `python3` and `mlx-lm`
2. In app Settings:
   - Provider: `Local`
   - Add one or more local model entries (`Model name` + `Model folder path`)
3. Select a configured local model from the Local model dropdown

## Codex Skills Bundle

Reusable prompt templates also live in:

- `/Users/espenmac/Code/ClipboardRefinerV2/.codex/skills/post-enhancer-prompts/SKILL.md`
- `/Users/espenmac/Code/ClipboardRefinerV2/.codex/skills/post-enhancer-prompts/templates.json`

## Privacy

- History/cache are local files on-device
- No telemetry by default
- Optional local perf telemetry can be enabled with `CLIPBOARD_REFINER_PERF=1` (emits JSON lines to stderr)
- With Local provider, prompts stay on-device
