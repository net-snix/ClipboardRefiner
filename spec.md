# ClipboardRefiner Product Specification

## Overview

ClipboardRefiner is a macOS menu bar application that leverages AI to refine, rewrite, and explain text. It provides frictionless text refinement through multiple access methods: menu bar, right-click Services, Siri Shortcuts, and global hotkeys.

**Target Platform:** macOS 13.0+
**Business Model:** One-time purchase (paid app with perpetual license)
**Distribution:** Multiple channels (Mac App Store + direct download/Homebrew)

---

## Core Functionality

### Rewrite Styles

Eight built-in styles, each with its own default aggressiveness setting:

| Style | Purpose | Default Aggressiveness |
|-------|---------|------------------------|
| Proofread | Fix grammar and improve clarity | Low |
| Shorter | Condense while keeping key information | Medium |
| More Formal | Professional, business-appropriate language | Low |
| More Casual | Friendly, conversational tone | Medium |
| Less Cringe | Remove buzzwords and marketing-speak | Medium |
| Enhance X Post | Optimize for X/Twitter engagement | High |
| Enhance AI Prompt | Improve prompts for better AI responses | Medium |
| Expand/Elaborate | Add detail and depth to brief text | Medium-High |

**Explain Feature:** Separate from rewrite styles, accessible via dedicated button. Produces meta-content explaining what the input text is and means, rather than rewriting it.

### Custom Styles

Users can create custom styles with their own prompts:
- **Storage:** In-app settings (not external files)
- **Editor:** Simple textarea (no syntax highlighting)
- **Management:** Create, edit, delete custom styles
- **Limit:** No hard limit, but reasonable cap for UI sanity

---

## AI Provider Support

### Supported Providers

1. **OpenAI** (gpt-4o, gpt-4o-mini, gpt-5.2)
2. **Anthropic** (claude-4.5-sonnet)
3. **xAI** (grok-4-1-fast, grok-4-1-fast-reasoning-latest)
4. **Local** (on-device models via configured model paths)

### Provider Selection Philosophy

New providers are added based on personal use case, not user demand or strategic coverage.

### Unified Reasoning Abstraction

Rather than per-provider settings (OpenAI reasoning effort, Claude extended thinking, etc.), implement a unified "thinking depth" slider that maps to each provider's equivalent feature.

### Local LLM Support

- **Configuration:** Users provide model folder paths in Settings
- **Selection:** Active local model chosen from configured dropdown
- **Use case:** Privacy-conscious users, offline usage

---

## User Interface

### Menu Bar Popover

**Dimensions:**
- Width: Adaptive based on screen size (smaller screens get narrower popover)
- Height: Scalable based on content

**Components:**
1. **Top Bar:** Title, status indicator, history button, settings menu
2. **Input Section:** Scrollable text area (3-20 lines)
3. **Action Row:**
   - Refine button (primary)
   - Explain button (secondary)
   - Style picker dropdown
4. **Result Section:** (appears after refinement)
   - Readonly output text
   - Redo button (uses current settings, not original)
   - Copy button
5. **History Section:** (collapsible)

**Empty State UX:** When API key is missing/invalid, show inline helper text near disabled Refine button: "Set up API key in settings"

### Detachable Window Mode

Add ability to detach the popover into a resizable floating window for longer text work:
- Button to pop out into separate window
- Window is fully resizable
- Returns to menu bar popover when closed

### Diff Highlighting

Optional toggle in settings to show inline diff highlighting in result section:
- Additions highlighted (green/underline)
- Deletions shown (red/strikethrough)
- Toggle in Behavior settings tab

---

## Settings

### Provider Tab
- Provider selection radio/dropdown
- Model picker per provider
- API key management (Keychain storage)

### Behavior Tab
- Quick behavior (Interactive vs Quick Replace)
- Streaming enabled toggle
- Auto-copy result toggle
- **Auto-load clipboard toggle** — Allow users to disable automatic clipboard loading on menu open (privacy feature for sensitive data)
- Aggressiveness slider (global default)
- Reasoning effort (unified slider when applicable)
- Diff highlighting toggle

### History Tab
- Enable/disable history
- Export to JSON
- Clear history

### Custom Styles Tab
- List of custom styles
- Add/edit/delete interface
- Simple textarea for prompt editing

### About Tab
- App info and version
- Links to support/feedback

---

## Access Methods

### 1. Menu Bar
- Click icon to open popover
- Auto-loads clipboard content (if setting enabled)
- Select style, click Refine

### 2. macOS Services (Right-click)
- "Open Clipboard Refiner" — Opens menu bar with selected text
- "Rewrite Interactive" — Shows popup with Replace/Copy options
- "Rewrite Quick" — Instant replace or interactive (configurable)

**Safety:** Original text preserved in history for recovery (when history enabled)

**Testing needed:** Service conflicts with Grammarly, Raycast, Notion, and other apps with Services

### 3. Siri Shortcuts
- Current: Basic refine intent
- Future consideration: Style parameter, batch processing

### 4. Global Keyboard Shortcuts

**Configurable hotkeys:**
- Open menu bar
- Refine clipboard directly
- Per-style shortcuts (e.g., Cmd+Shift+1 for Proofread, Cmd+Shift+2 for Shorter)

Power users can bind different hotkeys to different styles for maximum efficiency.

---

## Streaming & Error Handling

### Streaming Behavior
- Real-time SSE parsing for live output
- Toggle to enable/disable streaming

### Stream Failure Recovery
When streaming fails mid-response (network hiccup, rate limit):
1. **Preserve partial result** in output field
2. **Show retry button** to continue/restart
3. Error message explains what happened

### Context Window Overflow
When input text exceeds model's context limit:
- **Show error** with clear message about limits
- Display approximate character/token limit
- Do not auto-truncate or chunk (user must shorten input)

---

## Usage Tracking

### Aggregated Summaries
Dashboard page showing:
- Daily usage totals (tokens, estimated cost)
- Weekly/monthly aggregation
- Charts/graphs for visualization
- Per-provider breakdown

### Data Tracked
- Input tokens
- Output tokens
- Model used
- Estimated cost (based on public pricing)
- Timestamp

### Privacy
- Data stored locally only
- No server-side analytics

---

## History

### Storage
- Location: UserDefaults (JSON)
- Cap: 100 entries (lower if performance issues arise)
- Retention: Indefinite until cleared

### Entry Data
- Original text
- Refined text
- Style used
- Provider/model
- Timestamp
- Token usage (for usage tracking)

### Features
- Search/filter entries
- Click to load into input
- Export to JSON
- Clear all

---

## Aggressiveness System

### Curve
Exponential: `temperature = pow(aggressiveness, 2) * 0.8 + 0.2`

This provides finer control at lower values where precision matters most.

### Per-Style Defaults
Each style has its own sensible default:
- Proofread: ~0.15 (minimal changes)
- Shorter: ~0.35 (moderate restructuring)
- Enhance X Post: ~0.65 (significant creative freedom)

User can override per-use; global setting serves as fallback.

---

## Internationalization

### Multi-language Handling
- Prompts instruct LLM to preserve multiple languages
- Tested with mixed-language content (code comments, multilingual emails)
- Works well in current implementation

### UI Localization
- Not currently planned
- English-only interface

---

## Technical Architecture

### State Management
SwiftUI native approach with Combine:
- `@Published` properties in managers
- `@ObservedObject` in views
- No external state management library needed

### Key Storage
- API keys: macOS Keychain
- Settings: UserDefaults
- History: UserDefaults (JSON)

### Logging
- Location: `~/Library/Application Support/ClipboardRefiner/Logs/`
- Retention: 7 days
- **Audit needed:** Verify logs don't contain refined text content

---

## Quality Assurance

### Memory Profiling
- **Status:** Not yet profiled
- **Action:** Run Instruments memory profiling for extended sessions
- **Focus:** History growth, streaming buffer handling

### Accessibility
- **Status:** Not a priority
- **Baseline:** SwiftUI default accessibility
- VoiceOver not explicitly tested

### Service Conflicts
- **Status:** Not extensively tested
- **Action:** Test alongside Grammarly, Raycast, Notion, Bear

---

## Roadmap Summary

### Planned Features
1. Configurable global hotkeys (per-style shortcuts)
2. Detachable floating window mode
3. Adaptive popover width
4. Local LLM support (path-based model selection)
5. Custom user-defined styles
6. Usage tracking dashboard with aggregated summaries
7. Per-style default aggressiveness
8. Stream failure recovery with partial preservation
9. Diff highlighting toggle
10. Auto-load clipboard toggle (privacy)
11. Inline helper text for missing API key
12. "Expand/Elaborate" built-in style
13. Context overflow error handling

### Not Planned
- Translation style (rely on LLM general capability)
- Image/OCR input
- Cloud sync / collaborative features
- Deep Siri Shortcuts integration (current is sufficient)
- App-specific plugins (Services covers use cases)

### Deferred
- Deeper Shortcuts parameters (style selection, batch)
- Extensive accessibility testing
- UI localization

---

## Design Principles

1. **Minimal friction:** Text refinement should be fast and unobtrusive
2. **User responsibility:** Tool provides capability, user decides ethical use
3. **Trust the LLM:** Rely on model training for style evolution (e.g., "cringe" detection)
4. **Simple over complex:** SwiftUI native patterns, no over-engineering
5. **Power user friendly:** Hotkeys, custom styles, but not at cost of simplicity
6. **Privacy respecting:** Local storage, user's own API keys, optional auto-load

---

## Version History

- **Current:** Feature-complete core with OpenAI, Anthropic, xAI support
- **This spec:** Documents current state + planned enhancements

---

*Spec generated from product interview on 2024-12-29*
