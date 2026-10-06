---
name: background-computer-use
description: 在 Windows 上以「后台、不打扰用户」的方式操作桌面 App 与浏览器。当需要点击/输入/读窗口/抓网页，而用户可能正在用电脑时使用。
whenToUse: 需要操控本机 GUI（桌面应用或浏览器）时；用户说"不要弹窗口""后台执行""别抢我焦点"时；需要读取任意窗口内容时。
---

# Windows 后台操作

## 铁律

1. **默认走后台**。用户很可能正在看视频或打字。优先 `invoke` / `set_value` / `toggle` / `scroll` 这类**无光标**动作。
2. **不要用真鼠标**：`cursor:true`、`click_point`、`drag`（默认走真鼠标）都会移动用户的鼠标指针。
3. **需要可见窗口时**，先 `Win+Ctrl+D` 建虚拟桌面，在里面操作；结束 `Win+Ctrl+←` 切回，必要时 `Win+Ctrl+F4` 关掉。
4. 涉及代理 / VPN 的改动，先确认当前网络是否允许（比如校园网下通常禁止）。

## 工具分工（重要，别选错）

| 场景 | 用哪套 | 关键点 |
|---|---|---|
| 操作任意桌面 App（含最小化 / 被遮挡） | `umbriel` 的 `list_windows` → `attach` | attach 后**直接**用返回的 ref |
| 只读窗口内容、不动它 | `desktop_snapshot` / `read_table` / `ocr` / `capture_window` | — |
| 系统诊断 | `list_processes` / `process_info` / `list_connections` / `read_event_log` / `list_volumes` / `list_services` / `list_firewall_rules` | **不需要 shell** |
| 浏览器跑脚本、抓页面、**无登录态** | `playwright` 那套（无头浏览器） | `browser_snapshot` / `browser_find` 比截图省 token |
| 操作**用户自己的**浏览器（带登录态） | 宿主自带的浏览器绑定工具（若有） | 通常需要显式授权 |
| 文件 / 目录 / 命令 | 宿主自带的 read / write / edit / glob / grep / shell | **能用 CLI 就别用 GUI**，可靠得多 |

## umbriel 使用要点

- `attach` 之后**直接**用返回的 ref，不必再补一次 `desktop_snapshot`。
- **ref 只对最近一次快照有效**（形如 `e49#3`）。每个动作都会返回新树或 Δ（增量），永远用最新的 ref；旧 ref 会被**拒绝**而不是错点。
- 动作结果里出现 **⚠** = 这一步实际**抢了前台**（该控件没有自己的 HWND，只能走 UIA pattern）。想彻底避免就改用 `invoke` / `set_value` / `toggle`。
- 高完整性窗口（任务管理器、部分游戏平台）有 **UIPI 墙**，非管理员宿主驱动不了——别硬试。
- `cloaked: shell-hidden` 的窗口 UIA 树可能读空（不是真的没有），先 `manage_window {action:"raise"}`。
- 高密度窗口（大表格 / 图标墙）加 `desktop_snapshot {maxNodes}`，或用 `{root}` 收窄子树。
- 权限档位由环境变量 `UMBRIEL_PROFILE` 决定：`readonly`(41 工具) / `safe`(76，观察+无光标控制+窗口管理) / `full`(99，含注册表、进程、文件系统)。

## 浏览器使用要点

- 浏览器里的网页控件**同样没有独立 HWND**，所以对网页表单 `set_value` / `invoke` 基本都会抢一下前台——这是平台限制，不是出错。
- 想不抢前台地操作浏览器，优先用宿主自带的**浏览器绑定工具**（走 CDP，不需要激活窗口）。
- **后台标签页没有无障碍树**——要先把它切成当前标签，才能读到内容。

## 典型流程

1. `list_windows` → 拿到目标窗口的 hWnd
2. `attach {hWnd}` → 得到 ref 树
3. `invoke` / `type` / `set_value` / `toggle{state}` 执行
4. 需要"看"时：`screenshot`（PrintWindow → WGC → 区域，逐级降级）/ `capture_window`（被遮挡、GPU 合成）/ `ocr`（没有无障碍树时）
5. 等状态：`wait_for` / `wait_idle` / `wait_visual_idle` / `wait_responsive`（判断窗口是不是卡死了）

## 常见坑

- 表单类网页控件只能"展开/收起"，不能直接按文本选值——`select_option` 会失败，改用 `expand` + 选列表项。
- 文件对话框、系统级弹窗属于**另一个窗口**，要重新 `list_windows` + `attach`。
