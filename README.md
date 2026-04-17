<div align="center">

# whisper-toggle

**Press once to record. Press again to transcribe and paste.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![AUR](https://img.shields.io/badge/AUR-whisper--toggle-1793d1?logo=archlinux&logoColor=white)](https://aur.archlinux.org/packages/whisper-toggle)
[![whisper.cpp](https://img.shields.io/badge/powered%20by-whisper.cpp-green)](https://github.com/ggerganov/whisper.cpp)

Single-keybinding speech-to-text for Linux desktops.<br>
Pure bash. Local inference. No cloud. No latency.

---

```
Super+`  -->  🎙️ Recording...  -->  Super+`  -->  📋 Pasted!
```

</div>

## How It Works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  1st press   │────>│  Recording   │────>│ Transcribing │────>│   Pasted    │
│  Super + `   │     │  (sox/rec)   │     │ (whisper.cpp)│     │ (clipboard) │
└─────────────┘     └──────┬──────┘     └─────────────┘     └─────────────┘
                           │
                    ┌──────┴──────┐
                    │  2nd press   │  (or silence auto-stops)
                    │  Super + `   │
                    └─────────────┘
```

The server backend loads the model **while you speak** — by the time you stop talking, inference is nearly instant.

## Quick Start

```bash
# Install from AUR
yay -S whisper-toggle

# Interactive setup: GPU, model, backend, keybinding
whisper-toggle-setup
```

> **whisper.cpp required** — install via AUR (`yay -S whisper.cpp-cuda`) or [build from source](https://github.com/ggerganov/whisper.cpp). The setup wizard will guide you.

## Features

- **Single keybinding** — toggle recording on/off, transcription auto-pastes
- **Dual backend** — on-demand `whisper-server` (recommended) or direct `whisper-cli`
- **GPU accelerated** — CUDA, ROCm, Vulkan, or CPU fallback
- **X11 + Wayland** — auto-detects session, uses the right clipboard/paste tools
- **Interactive setup** — detects GPU, downloads models, configures your WM
- **XDG compliant** — config in `~/.config/`, models in `~/.local/share/`, temp in `/dev/shm/`
- **No daemon** — server starts and stops per-transcription, zero background footprint
- **Smart silence detection** — recording stops automatically when you stop speaking
- **Post-processing** — strips non-speech markers, trims whitespace, capitalizes

## Dependencies

<table>
<tr><th colspan="3">Required</th></tr>
<tr><td><code>bash</code></td><td><code>sox</code></td><td><code>curl</code></td></tr>
<tr><td><code>jq</code></td><td><code>libnotify</code></td><td><code>libpulse</code></td></tr>
<tr><th colspan="3">X11</th></tr>
<tr><td><code>xsel</code></td><td colspan="2"><code>xdotool</code></td></tr>
<tr><th colspan="3">Wayland</th></tr>
<tr><td><code>wl-clipboard</code></td><td colspan="2"><code>ydotool</code></td></tr>
<tr><th colspan="3">Optional</th></tr>
<tr><td colspan="3"><code>pciutils</code> (GPU detection in setup wizard)</td></tr>
</table>

## Keybindings

The setup wizard auto-detects your WM and offers to configure this for you.

<details>
<summary><b>i3</b></summary>

```
bindsym $mod+grave exec --no-startup-id whisper-toggle
```
</details>

<details>
<summary><b>sway</b></summary>

```
bindsym $mod+grave exec whisper-toggle
```
</details>

<details>
<summary><b>Hyprland</b></summary>

```
bind = $mainMod, grave, exec, whisper-toggle
```
</details>

<details>
<summary><b>GNOME</b></summary>

Configured via `whisper-toggle-setup` using gsettings, or manually:<br>
Settings > Keyboard > Custom Shortcuts
</details>

<details>
<summary><b>KDE</b></summary>

System Settings > Shortcuts > Custom Shortcuts > Add > Command/URL
</details>

## Configuration

`~/.config/whisper-toggle/whisper-toggle.conf`

```bash
BACKEND="server"              # "server" or "cli"
WHISPER_SERVER=""              # Path to whisper-server (auto-detected)
WHISPER_CLI=""                 # Path to whisper-cli (auto-detected)
WHISPER_MODEL="~/.local/share/whisper-toggle/models/ggml-small.en.bin"
WHISPER_PORT=58080             # Server backend port
WHISPER_DEVICE=0               # GPU index (-1 for CPU-only)
WHISPER_THREADS=4              # CPU threads for inference
WHISPER_LANGUAGE="en"          # Language code or "auto"
AUTOPASTE=1                    # Auto-paste after transcription
PASTE_METHOD="ctrl_v"          # "ctrl_v" or "shift_insert"
SILENCE_DURATION=3.0           # Seconds of silence before auto-stop
SILENCE_THRESHOLD=3            # Silence sensitivity (%)
```

## Models

| Model | Size | Speed | Quality | Best For |
|:------|-----:|:-----:|:-------:|:---------|
| `tiny.en` | 75 MB | ⚡⚡⚡⚡ | ★★ | Quick notes, low-end hardware |
| `base.en` | 142 MB | ⚡⚡⚡ | ★★★ | Everyday use |
| **`small.en`** | **466 MB** | **⚡⚡** | **★★★★** | **Recommended** |
| `medium.en` | 1.5 GB | ⚡ | ★★★★★ | High accuracy needs |
| `large-v3-turbo` | 1.6 GB | ⚡⚡ | ★★★★★ | Best speed/accuracy ratio |
| `large-v3` | 3.1 GB | ⚡ | ★★★★★ | Maximum accuracy |

Models are downloaded by the setup wizard to `~/.local/share/whisper-toggle/models/`.

## Backends

### `server` (recommended)

```
[key press] ──> whisper-server starts ──> model loads ──> ┐
                recording starts ──────> audio captured ──> inference ──> paste
                                                           server killed
```

The model loads **in parallel** with your speech. No persistent daemon — the server is started and killed per use.

### `cli`

```
[key press] ──> recording starts ──> audio captured ──> whisper-cli runs ──> paste
```

Simpler, but slower — the model loads **after** you stop speaking.

## GPU Setup

The setup wizard detects your GPU(s) via `lspci` and recommends the right device.

| GPU | whisper.cpp Package | Build Flag |
|:----|:-------------------|:-----------|
| NVIDIA | `whisper.cpp-cuda` | `-DGGML_CUDA=ON` |
| AMD | `whisper.cpp-hip` | `-DGGML_HIP=ON` |
| Any | `whisper.cpp-vulkan` | `-DGGML_VULKAN=ON` |
| None | `whisper.cpp` | (default) |

## Troubleshooting

<details>
<summary><b>No sound recorded</b></summary>

Check that PulseAudio/PipeWire is running and `rec` can access your mic:
```bash
rec -q -t wav /tmp/test.wav rate 16k
```
</details>

<details>
<summary><b>Server failed to start</b></summary>

Check the log for whisper-server errors:
```bash
cat /tmp/whisper-toggle.log
```
Common causes: wrong GPU device index, missing CUDA/Vulkan drivers, model file not found.
</details>

<details>
<summary><b>Nothing pastes</b></summary>

**X11:** Install `xsel` and `xdotool`<br>
**Wayland:** Install `wl-clipboard` and `ydotool`, ensure `ydotoold` is running<br>
If your target app pastes more reliably with `Shift+Insert` (e.g. when using whisper on a terminal), set `PASTE_METHOD="shift_insert"` in your config.
</details>

<details>
<summary><b>Double triggers</b></summary>

The 500ms debounce should prevent this. If your WM sends multiple key events, use `exec --no-startup-id` (i3) or increase the debounce in the script.
</details>

<details>
<summary><b>whisper-server / whisper-cli not found</b></summary>

The script searches `~/whisper.cpp/build/bin/`, `~/.local/bin/`, `/usr/local/bin/`, and `/usr/bin/`. You can also set `WHISPER_SERVER` / `WHISPER_CLI` explicitly in the config.
</details>

---

<div align="center">
<sub>MIT License &mdash; built with <a href="https://github.com/ggerganov/whisper.cpp">whisper.cpp</a></sub>
</div>
