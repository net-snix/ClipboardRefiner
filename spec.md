# ClipboardRefiner Product Specification

_Last verified against code on 2026-02-25._

## Overview

ClipboardRefiner is a native macOS menu bar application for rewriting or explaining text with cloud or local models.

- Target platform: macOS 15.0+
- Current Xcode project language mode: Swift 5.0
- App form factor: menu bar popover + settings window

## Current Shipped Scope (2026-02)

### Core User Flows

1. Open menu bar app, edit/paste text, choose provider/model/style, run rewrite or explain.
2. Optionally attach up to 4 images (cloud providers only) as additional context.
3. Copy or share output.
4. Use macOS Services to open the app prefilled with selected text.
5. Use App Intent to rewrite current clipboard text (style parameter supported).

### Rewrite Styles (Shipped)

`Explain` is a separate action, not part of the rewrite-style picker.

| Style | Purpose |
|-------|---------|
| Proofread | Fix grammar and clarity while preserving intent |
| Shorter | Condense and remove repetition |
| More formal | Professional tone |
| More casual | Conversational tone |
| Less cringe | Remove hype/buzzword phrasing |
| Enhance X post | Improve for X-style post readability/engagement |
| Enhance AI prompt | Improve prompt clarity and structure |

### Providers and Models (Shipped)

1. OpenAI
   - `gpt-5.2`
   - `gpt-5.1-2025-11-13`
2. Anthropic
   - `claude-sonnet-4-6`
   - `claude-opus-4-6`
3. xAI
   - `grok-4-1-fast`
   - `grok-4-1-fast-reasoning-latest`
4. Local
   - Path-based local model configuration
   - Text-only (no image attachment support)

### Settings Surface (Shipped)

#### Provider tab
- Provider selection
- Model defaults per provider
- API key management (Keychain-backed for cloud providers)
- Local model path list/add/remove/select
- Load/unload local model controls
- Keep-local-model-loaded toggle

#### Behavior tab
- Default rewrite style
- Prompt skill selection
- Rewrite aggressiveness slider
- System prompt override editor per style
- Runtime toggles:
  - Streaming response updates
  - Auto-copy after success
  - Auto-load clipboard on open
  - Keep local model loaded
  - Enable offline cache fallback
- Quick service behavior picker (interactive popup vs quick replace)

#### History tab
- Enable/disable local history
- Export history JSON
- Clear history
- Clear offline cache

#### About tab
- Product summary and feature bullets

### Access Methods (Shipped)

1. Menu bar app (primary)
2. macOS Services (NSServices in `Info.plist`)
   - `Rewrite with Clipboard Refiner`
   - `Explain with Clipboard Refiner`
   - Both open the menu workflow with prefilled text
3. App Intent / Shortcuts
   - `Rewrite Clipboard` intent with style parameter

## Streaming and Completion Behavior (Shipped)

- SSE streaming for cloud providers.
- Stream UI delivery is coalesced to ~30 FPS in `RewriteEngine`.
- Final pending stream output is flushed before completion callback.
- Streaming can be toggled in Settings.
- If a failure occurs after partial streamed output, current partial text remains visible.

## Performance Hardening Shipped (2026-02)

- Coalesced stream UI delivery (~30 FPS).
- `RewriteEngine.currentOutput` is no longer `@Published`.
- Cancel handler path uses non-blocking async dispatch in `ProcessCancellable`.
- Result panel height measurement suppressed during active streaming.
- Window sizing updates debounced.
- Pasted image-path detection has early guard checks before diffing.
- Settings write churn reduced:
  - Aggressiveness commits on slider release.
  - System prompt commits are debounced (~300ms).

## Known Performance Caveats (Current)

- Providers still dispatch each stream chunk to main-thread closures before engine-level coalesced delivery.
- Streaming still propagates full accumulated output strings repeatedly, which can be expensive on very long outputs.
- Local model lifecycle uses semaphore waits on a background queue for load/unload paths.
- Image attachment flow can spike memory due to raw bytes + base64 + data URL + JSON request body.
- `rewriteSync` is a blocking API and should not be used from main-thread contexts.

## Data Storage and Privacy (Current)

- API keys: macOS Keychain.
- Settings + rewrite history: UserDefaults.
- Offline rewrite cache: local JSON file in Application Support (`rewrite-cache.json`).
- History cap: 150 entries.
- Offline cache cap: 300 entries.
- No telemetry by default.
- Optional local perf telemetry can be enabled with `CLIPBOARD_REFINER_PERF=1` (JSON lines to stderr, local process only).
- Local provider keeps prompt/model execution on-device.

## Not Yet Shipped / Planned

1. Custom user-defined rewrite styles + dedicated settings tab.
2. Diff-highlighting toggle integrated in runtime UI.
3. Global keyboard shortcut registration and management.
4. Detachable/floating long-form editor window mode.
5. Stream failure retry control in result UI.
6. Usage tracking dashboard/analytics view (local aggregates).
7. Deeper Shortcuts workflows (batch/more parameters).

## Version Status

- Current: production-oriented core app with OpenAI, Anthropic, xAI, and local provider support.
- This spec: explicitly separated into shipped behavior vs planned work to avoid roadmap/current-state drift.
