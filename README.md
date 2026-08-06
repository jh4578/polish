# Polish

A macOS menu-bar utility: select text in any app, press **⌥P**, and a small floating input box appears. Type an instruction (or just hit Enter for the default "polish"), and the text is rewritten and pasted over your selection. The box stays open so you can keep refining with follow-up instructions.

Pure Swift/AppKit, ~284 KB, no runtime dependencies.

## Backend: direct Codex call on your ChatGPT subscription

- Calls the Codex backend directly (`https://chatgpt.com/backend-api/codex/responses`, the same endpoint the Codex CLI uses) with `URLSession` — **no API key, no Node, no SDK**
- Auth reuses the local Codex **ChatGPT subscription login** (`~/.codex/auth.json`); the access token is read and, when expired, refreshed via the standard OAuth refresh-token flow. Usage counts against your ChatGPT plan.
- Model `gpt-5.5` with `reasoning.effort: "none"` — the fastest combination a ChatGPT-subscription account allows (see Notes on speed).

## Usage

1. On first launch, grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility). Required for reading the selection and auto-pasting. **Re-grant after every rebuild** (see Known limitations).
2. Select text in any app and press **⌥P** (change it in menu-bar icon → 设置…)
3. In the box:
   - Press **Enter** with an empty field = default polish
   - Or type an instruction first, e.g. "translate to English", "make it more formal", "cut it to half the length"
4. The result replaces the selected text automatically. The box stays open — type another instruction to refine (it undoes the previous paste and pastes the new version).
5. **Esc** closes the box (and restores your original clipboard)
6. Menu-bar icon → "开机自动启动" to launch at login
7. Menu-bar icon → "设置…" for: hotkey, panel on/off (off = instant polish with a small HUD, no popup), and the default polish prompt

## Requirements

- Codex signed in with a ChatGPT account on this Mac (desktop app or CLI — they share the login at `~/.codex/auth.json`)

## Security

- Credentials are never bundled with the app or stored in this repository.
- Polish reads the existing Codex login from `~/.codex/auth.json` only at runtime.
- Authentication data is sent only to the OpenAI endpoints declared in the source: `chatgpt.com` and `auth.openai.com`.
- Local credentials, build output, and packaged apps are excluded from version control.

## Build & install

```bash
bash build_app.sh                     # produces dist/Polish.app (~284 KB)
ditto dist/Polish.app /Applications/Polish.app
open /Applications/Polish.app
```

## Layout

```
Sources/Polish/
  main.swift                  # entry point (menu-bar accessory app)
  AppDelegate.swift           # status item, Accessibility prompt, launch-at-login (SMAppService)
  HotKey.swift                # global hotkey registration (Carbon RegisterEventHotKey)
  HotKeyConfig.swift          # persisted hotkey setting (default ⌥P) + display names
  HotKeyRecorderController.swift # "change hotkey" recorder window
  Settings.swift              # persisted settings (panel on/off, default prompt)
  SettingsWindowController.swift # settings window
  ProgressHUD.swift           # tiny floating HUD for instant-polish mode
  TextCapture.swift           # simulated ⌘C/⌘V/⌘Z, clipboard snapshot & restore
  PolishPanelController.swift # minimal floating input box (doesn't steal target-app focus)
  CodexClient.swift           # direct backend call (URLSession + SSE parsing)
  CodexAuth.swift             # reads/refreshes the ChatGPT login token from ~/.codex/auth.json
build_app.sh                  # packages the .app
```

## Customizing

- **Hotkey / panel on-off / default polish prompt**: menu-bar icon → 设置… (stored in UserDefaults)
- **Model / reasoning effort**: `model` and the `reasoning.effort` in `CodexClient.swift`

## Notes on speed

A ChatGPT-subscription login is locked to `gpt-5.5` server-side (gpt-5, gpt-5.1, gpt-5-mini, gpt-5.5-codex are all rejected), and `reasoning.effort` can be at most `none`. That yields ~1.6 s to first token and ~2 s total — the floor for this account type. Sub-second latency would require an API key plus a small model (e.g. gpt-4o-mini), which is intentionally not used here.

## Known limitations

- Ad-hoc code signing changes the binary's hash on every rebuild, so macOS invalidates the Accessibility grant each time. After rebuilding, re-toggle Polish in System Settings → Accessibility. (A stable self-signed certificate would fix this permanently.)
- Multi-round replacement works by undo-then-paste; a few apps (some web rich-text editors) may handle undo differently. First-round replacement works anywhere ⌘C/⌘V works.
- With no selection, you can still type an instruction to generate text — it's inserted at the cursor.
