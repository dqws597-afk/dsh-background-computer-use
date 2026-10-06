# dsh-background-computer-use

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey.svg)]()
[![DSH](https://img.shields.io/badge/DSH-0.2.x-4B8BBE.svg)](https://github.com/deepseek-ai/deepseek-harness)
[![MCP](https://img.shields.io/badge/MCP-stdio-6E4AFF.svg)](https://modelcontextprotocol.io)

English | [简体中文](./README.md)

A configuration template that gives **DeepSeek Harness (DSH)** background desktop and browser control.

The template wires two MCP servers into DSH, enabling an agent to operate Windows applications and a browser while honouring a strict constraint: **it does not steal keyboard focus, does not move the mouse pointer, and does not create visible windows**.

> This repository is a **configuration template**, not standalone software. It consists of configuration fragments, an installation script and documentation, and requires DSH at runtime. It may also serve as a reference for other agent projects.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Design Rationale](#2-design-rationale)
- [3. Architecture](#3-architecture)
- [4. Capabilities](#4-capabilities)
- [5. Requirements](#5-requirements)
- [6. Installation](#6-installation)
- [7. Configuration](#7-configuration)
- [8. Verification](#8-verification)
- [9. Troubleshooting](#9-troubleshooting)
- [10. Files](#10-files)
- [11. Glossary](#11-glossary)
- [12. License](#12-license)
- [Acknowledgements](#acknowledgements)
- [Disclosure](#disclosure)

---

## 1. Overview

A general-purpose Computer-Use Agent needs a mechanism to *perceive an interface → locate a control → dispatch input*. This template provides such a mechanism for **Windows**, and its defining choice is to **prefer structured interface information published by the system over screen pixels**, which allows the agent to work while the user keeps using the machine.

The template covers two capabilities:

| Capability | Implementation | Scope |
|---|---|---|
| Desktop application control | [Umbriel](https://github.com/ObscuritySRL/umbriel) | Any Windows desktop program, including minimised and occluded windows |
| Browser automation | [Playwright MCP](https://github.com/microsoft/playwright-mcp) | Headless Edge / Chromium instances |

Both are integrated through the **Model Context Protocol (MCP)**. No changes to DSH source code are required.

---

## 2. Design Rationale

### 2.1 Inherent limits of pixel-based control

Conventional approaches rely on **screenshots plus pixel coordinates**: capture the screen, let a model estimate the target control's coordinates, then dispatch a mouse event at that point. This is straightforward and imposes no requirements on the target program, but it suffers from three problems:

1. **Uncertain localisation** — coordinates are estimates; a small layout shift or rendering difference causes a misclick;
2. **Invisible windows cannot be handled** — a window absent from the frame cannot be located, so minimised or occluded windows are out of reach;
3. **High context cost** — image tokens cost substantially more than the equivalent structured text.

### 2.2 The approach used here

Windows applications expose their interface structure through **UI Automation (UIA)**: control type, accessible name, current value, enabled state and bounds. That structure exists to support assistive technology (screen readers), but its information density and determinism make it equally suitable as an agent's control channel.

Consequences:

- Localisation is based on **control identity**, not coordinate estimates;
- Windows **not yet rendered on screen** can be operated;
- Every action returns a fresh structured snapshot, and element references (`ref`) carry a generation tag — **a stale reference is explicitly rejected rather than silently applied to the wrong target**.

### 2.3 Fallback

Programs that publish no UIA structure — typically full-screen DirectX applications such as games — cannot use this channel. The template retains a visual fallback: window capture, GPU-composited frame capture, OCR and template matching. The reliability of that fallback depends on the specific application and lies outside the guarantees of this template.

---

## 3. Architecture

```
User instruction
   │
   ▼
DSH agent loop
   │
   ▼
MCP tool registry
   │
   ├── mcp__umbriel__*      ──▶  Umbriel        ──▶  UI Automation / Win32
   │                                                  (cursor-free input routing)
   │
   └── mcp__playwright__*   ──▶  Playwright MCP ──▶  headless Chromium / Edge
```

Umbriel dispatches input to the target window through Windows messages and UI Automation patterns rather than moving the real cursor, so the user's mouse position and keyboard focus remain unchanged throughout.

---

## 4. Capabilities

### 4.1 Supported

| Capability | Notes |
|---|---|
| Desktop application control | Click, text entry, value setting, toggling, list selection, scrolling; minimised, occluded and background windows supported |
| Interface reading | Structured snapshots, data tables, text content, control state and bounds |
| System information | Processes, services, network connections, event logs, disks, scheduled tasks, firewall rules — no shell required |
| Window management | Move, resize, minimise, pin on top, snap, opacity |
| Browser automation | Headless loading, navigation, form filling and content extraction |
| Visual fallback | Window capture, occluded-window capture, OCR, colour and image matching |

### 4.2 Limitations

| Limitation | Cause |
|---|---|
| Cannot operate high-integrity (administrator) windows | UIPI isolation: a medium-integrity process may not dispatch input to a high-integrity window |
| Some controls briefly take the foreground | Controls without their own window handle (HWND) — common in WinUI / WPF / Electron — expose only UI Automation patterns, and the MSAA bridge requires activating the target first. The tooling flags this in its result |
| Full-screen DirectX applications expose no structure | Such programs publish no UIA tree; only the visual fallback applies |

> These limitations stem from platform mechanics, not from configuration. The second row can be made rarer by preferring actions built on `Invoke` / `Value` / `Toggle` patterns.

---

## 5. Requirements

| Dependency | Requirement | How to check |
|---|---|---|
| Operating system | Windows 10 / 11 | — |
| Node.js | ≥ 20 | `node --version` |
| DSH | 0.2.x | Starts normally |
| Network proxy | Optional | For external network access; know its listening port if used |

---

## 6. Installation

### 6.1 One-liner

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

### 6.2 Manual

```powershell
# 1. Install the Bun runtime
npm i -g bun

# 2. Install Umbriel
bun add -g umbriel

# 3. Install Playwright MCP
npm i -g @playwright/mcp

# 4. Download the browser binary
#    Note: this must use the Playwright bundled with @playwright/mcp
#    so that the binary revision matches what the runtime expects.
node "$env:APPDATA\npm\node_modules\@playwright\mcp\node_modules\playwright\cli.js" install chromium
```

---

## 7. Configuration

### 7.1 Location

The configuration file lives in the DSH profile directory:

```
~\.dsh\profiles\<profile name>\cordis.patch.yml
```

The desktop build of DSH normally uses `desktop`; the web build normally uses `web`. List `~\.dsh\profiles\` to confirm.

### 7.2 Content

Append the `- insert:` block from [`cordis.patch.yml.example`](./cordis.patch.yml.example) to the end of that file.

The file is a **patch layer**, and a top-level entry has one of two meanings:

| Form | Meaning |
|---|---|
| `- id: <id of an existing entry>` | Overrides that entry's configuration |
| `- insert: [...]` | **Adds** new entries |

> Writing a new entry as a top-level `- id: ...` makes the loader look for an existing entry with that id; when the lookup fails it is **skipped silently, with no error message**. New entries must go inside an `insert` list.

### 7.3 Fields to edit

| Field | Meaning | How to obtain |
|---|---|---|
| `command` (playwright) | Absolute path to `node.exe` | `(Get-Command node).Source` |
| `args[0]` (playwright) | Path to `@playwright/mcp`'s `cli.js` | Usually `%APPDATA%\npm\node_modules\@playwright\mcp\cli.js` |
| `<username>` (two places) | Your user directory name | `$env:USERNAME` |
| `--proxy-server` | Proxy listening address | Delete the flag and its value if unused |

### 7.4 Activation

DSH **hot-reloads** this file after saving. Changes normally take effect within a minute, with no restart.

---

## 8. Verification

Run the following prompts in a DSH session:

**Desktop channel**

> List all current windows

Expected: a window list including window handle, owning process and minimised state.

**Browser channel**

> Use playwright to open https://example.com and return the page title

Expected: `Example Domain`, with **no browser window appearing on the desktop**.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Configuration written, but no tools appear and no error is reported | The new entry was written at the top level instead of inside an `insert` list, so it was skipped silently | Adjust the form as described in [section 7.2](#72-content) |
| `Chromium distribution 'chrome' is not found` | Playwright MCP looks for a system Chrome by default | Add `--browser msedge`; unnecessary if Chrome is installed |
| The headless browser cannot reach the external network | MCP does not use the system proxy by default | Add `--proxy-server http://127.0.0.1:<port>` |
| Umbriel exits with code 255, reporting `bun is not installed in %PATH%` | `~/.bun/bin/umbriel.exe` is a launcher shim that requires `bun` on `PATH` at runtime | Invoke `umbriel/mcp.ts` directly with `bun.exe` |
| The browser binary is downloaded again at runtime | The binary was fetched with the system-wide Playwright, so its revision does not match what MCP expects | Use the Playwright bundled with `@playwright/mcp` (step 4 of [section 6.2](#62-manual)) |
| An action switches the foreground window | The target control has no HWND, so only the activation-based UI Automation path is available | A platform limitation that cannot be avoided; the tooling flags it in its result, and you can substitute a cursor-free action |

---

## 10. Files

| File | Purpose |
|---|---|
| `README.md` | Chinese documentation |
| `README.en.md` | This document |
| `LICENSE` | MIT licence |
| `install.ps1` | Dependency installation script |
| `cordis.patch.yml.example` | DSH configuration fragment to append to `cordis.patch.yml` |
| `SKILL.md` | Operating rules for the agent: tool selection, reference semantics, trigger conditions |

---

## 11. Glossary

| Term | Definition |
|---|---|
| **Computer-Use Agent** | An agent that observes and operates a graphical interface to complete tasks |
| **UI Automation (UIA)** | The Windows interface-structure access API, used by assistive technology and automation to read the control tree |
| **Accessibility tree** | The interface structure an application exposes through UIA, describing control type, name, state and position |
| **HWND** | The handle Windows assigns to a window. Whether a control owns an HWND determines which input-dispatch paths are available to it |
| **UIPI** | User Interface Privilege Isolation, which prevents lower-integrity processes from dispatching input to higher-integrity windows |
| **Focus** | The window or control currently receiving keyboard input |
| **MCP** | Model Context Protocol, a standard for exposing external tools to models |
| **stdio transport** | An MCP transport in which the client launches the server as a subprocess and communicates over standard input and output |
| **Headless mode** | Running a browser without creating a visible window |
| **Hot reload** | Automatically reloading configuration after a change, without restarting the process |
| **OCR** | Optical character recognition — reading text out of images |
| **ref (element reference)** | An identifier for a control within an interface snapshot, carrying a generation number; valid only for the snapshot that produced it |

---

## 12. License

Released under the [MIT License](./LICENSE).

---

## Acknowledgements

- [Umbriel](https://github.com/ObscuritySRL/umbriel) — background desktop control on Windows
- [Playwright MCP](https://github.com/microsoft/playwright-mcp) — browser automation
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) — MCP client and plugin infrastructure
- DeepSeek-V4.1-Flash — assistance in shaping the idea and validating the setup

---

## Disclosure

The code in this repository was written and provided by AI, and has been verified in a real Windows 11 + DSH 0.2.x environment. Feedback and improvement suggestions are welcome via Issues.
