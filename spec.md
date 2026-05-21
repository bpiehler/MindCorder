
# Functional Specification & High-Level Architecture

**Project Title:** MindCorder (Zero-Friction Thought Capture & AI Summary App)  
**Target Platform:** Pebble Round 2 (PR2) & Android/iOS Companion App  
**Document Version:** 1.0 (Phase 1 Local-First, Phase 2 BYOK)


## 1. Executive Summary & Core Value Proposition

MindCorder is an ambient, zero-friction audio memo capture tool designed specifically for the unique physical advantages of the Pebble Round 2. Unlike modern smartwatches that suffer from "battery anxiety," the PR2's 2-week battery life and high-density, low-power e-paper screen allow users to offload unstructured audio logging and ambient thoughts directly from the wrist without constant screen wake or charging management. 

The software utilizes a dual-device pipeline: low-overhead audio capture on-wrist via the Pebble Dictation API, paired with robust, local-first machine learning synthesis on a modern smartphone.


## 2. User Experience & Core Workflows

### Phase 1: Local-First Workflow

[Wrist Action]                     [Dictation UI]               [Haptic Pulse]
Long-Press Select Button  --->   "Listening..." (Capture) ---> Processing (Vibe)
|
[Markdown View on PR2]             [Phone Processing]                 v
Structured Bullet Points <---   Gemini Nano / Whisper <--- Send Text via AppMessage


1. **Initiation:** The user long-presses the **Select** hardware button on the PR2 from any state to immediately launch the app directly into voice capture.
2. **Capture:** The watch activates the dual microphones using the Dictation API. The screen shows a low-energy recording graphic. The user speaks unfiltered, unstructured stream-of-consciousness thoughts (up to the system buffer limit, typically ~30–60 seconds of text per chunk).
3. **Transmission:** The converted text block streams automatically over Bluetooth to the smartphone companion app using `AppMessage`.
4. **Local Synthesis:** The companion app processes the text strictly on-device using OS-level local models (Android AICore / iOS CoreML Frameworks).
5. **Feedback Loop:** Once synthesized, the phone pushes a structured Markdown text summary back to the watch. The watch emits a double haptic pulse (Linear Resonance Actuator) to alert the user without requiring them to look down.
6. **Review:** The user glances at the 200 DPI circular display to read highly legible, clean bullet points formatted from their raw rambling.

### Phase 2: Power User Expansion (BYOK)

Adds a settings toggle inside the Mobile Configurator:
* **Storage Provider:** Save directly to a local file, or pipe output to a GitHub Gist / Notion Webhook.
* **Model Router:** Toggle from "On-Device (Free)" to "Cloud API (Custom Key)". Users paste an Anthropic or OpenAI API key. This unlocks massive context windows, deep reasoning, multi-language translation formatting, and custom system instruction templates.


## 3. High-Level System Architecture

The architecture enforces strict separation of concerns: the watch functions as an input/output terminal, while the phone acts as the central engine.


```

+-----------------------------------------------------------------------------------+
|                            PEBBLE ROUND 2 (Wrist App)                             |
|                                                                                   |
|  +---------------------+      +---------------------+      +-------------------+  |
|  |    Dictation API    | ---> |    AppMessage API   | ---> |  C Graphics Layer |  |
|  | (Dual Microphone)   |      |  (Bluetooth Buffer) |      | (260x260 Circular)|  |
|  +---------------------+      +---------------------+      +-------------------+  |
+------------------------------------------|----------------------------------------+
| Bluetooth SPP / BLE
v
+-----------------------------------------------------------------------------------+
|                        SMARTPHONE COMPANION (Mobile App)                          |
|                                                                                   |
|     +-----------------------------------------------------------------------+     |
|     |                         Orchestration Router                          |     |
|     +-----------------------------------------------------------------------+     |
|                                |                                 |                |
|               (Phase 1)        v               (Phase 2 Toggle)  v                |
|        +-------------------------------+       +--------------------------------+ |
|        |      On-Device Inference      |       |        Cloud AI Pipeline       | |
|        | ----------------------------- |       | ------------------------------ | |
|        | - Android: AICore/Gemini Nano |       | - User-Supplied Keys (BYOK)    | |
|        | - iOS: CoreML Text Engine     |       | - Anthropic Claude / OpenAI    | |
|        +-------------------------------+       +--------------------------------+ |
|                                |                                 |                |
|                                +---------------+-----------------+                |
|                                                |                                  |
|                                                v                                  |
|                                   +--------------------------+                    |
|                                   |  Markdown Output Parser  |                    |
|                                   +--------------------------+                    |
+-----------------------------------------------------------------------------------+


### Component Breakdown

#### A. Watch Firmware Layer (C / Pebble SDK)
* **`dictation_session_create()`**: Instantiates the voice session pipeline. It bypasses native confirmation dialogue (`dictation_session_enable_confirmation(false)`) to maintain the "zero-friction" principle.
* **Data Log Storage**: Implements a circular memory ring buffer using the Pebble `Storage` API to cache the last 5 synthesized summaries locally on the wrist for offline reading.
* **UI Layout Engine**: Adapts dynamically to the 260x260 resolution. Font scale is optimized at a compact but sharp density, taking full advantage of the 200 DPI hardware to fit complete sentences within the circular bounds without aggressive edge clipping.

#### B. Mobile Orchestration Layer (Java/Kotlin for Android, Swift for iOS)
* **Communication Interface**: Listens via `PebbleKit` libraries for incoming text buffers tied to the application's unique UUID.
* **Inference Pipeline (Phase 1 - Local-First):**
  * **Android**: Binds directly to the background `AICore` system service. It feeds the raw dictation payload into **Gemini Nano** alongside a static system prompt: *"Format the following messy transcript into a clean, concise bulleted summary using Markdown. Remove all filler words. Maximum 3 structural lines."*
  * **iOS**: Integrates local text transformation models via **CoreML**.
* **Inference Pipeline (Phase 2 - Cloud BYOK):**
  * Reads client encryption-secured preferences. If active, it skips local inference and maps an asynchronous HTTPS POST query to `api.anthropic.com/v1/messages` or `api.openai.com/v1/chat/completions`, dropping the raw input directly into highly accurate reasoning engines (e.g., Claude 3.5 Sonnet).


## 4. Technical Constraints & Mitigations

| Hardware / SDK Reality | App Strategy / Mitigation |
| :--- | :--- |
| **Dictation Timeout Window**<br>The Pebble Dictation engine cuts off automatically after several seconds of silence to preserve battery. | The mobile app accumulates chunks continuously. When a session terminates on-wrist, the phone processes the chunk immediately but allows the user to immediately trigger an "append session" via a single physical button tap. |
| **AppMessage Payload Limits**<br>Bluetooth buffers between Pebble and phone have explicit size limits (typically 2KB - 4KB). | Large text arrays sent from the phone back to the watch are dynamically split by the companion app into structured, numbered blocks. The watch pieces these segments back together before rendering them on the UI. |
| **No Native Background Local LLM on Old Phones**<br>Older Android devices don't have AICore or Gemini Nano hardware enablement. | The companion app checks for system hardware features during the first run. If local hardware-accelerated NPU models are absent, the application skips Phase 1 defaults and prompts the user to enter a cloud API key (Phase 2 functionality) to execute. |
