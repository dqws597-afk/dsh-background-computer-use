# dsh-background-computer-use

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey.svg)]()
[![DSH](https://img.shields.io/badge/DSH-0.2.x-4B8BBE.svg)](https://github.com/deepseek-ai/deepseek-harness)
[![MCP](https://img.shields.io/badge/MCP-stdio-6E4AFF.svg)](https://modelcontextprotocol.io)

为 **DeepSeek Harness (DSH)** 增加后台桌面与浏览器操作能力的配置模板。

本模板在 DSH 中接入两个 MCP 服务器，使 Agent 具备操作 Windows 应用与浏览器的能力，并满足以下约束：**不抢占键盘焦点、不移动鼠标指针、不创建可见窗口**。

> 本仓库是**配置模板**，不是独立软件。它由若干配置片段、安装脚本与说明文档组成，需配合 DSH 使用，亦可作为其他 Agent 项目的参考。

---

## 目录

- [1. 概述](#1-概述)
- [2. 设计取舍](#2-设计取舍)
- [3. 架构](#3-架构)
- [4. 能力范围](#4-能力范围)
- [5. 环境要求](#5-环境要求)
- [6. 安装](#6-安装)
- [7. 配置](#7-配置)
- [8. 验证](#8-验证)
- [9. 故障排查](#9-故障排查)
- [10. 文件说明](#10-文件说明)
- [11. 术语表](#11-术语表)
- [12. 许可](#12-许可)
- [致谢](#致谢)
- [声明](#声明)

---

## 1. 概述

通用计算机操作 Agent（Computer-Use Agent）通常需要一套“感知界面 → 定位控件 → 派发输入”的机制。本模板提供一套面向 **Windows** 的实现，其特点是**优先使用系统提供的结构化界面信息，而非屏幕像素**，因而能够在用户继续使用计算机的同时完成操作。

模板包含两部分能力：

| 能力 | 实现 | 适用范围 |
|---|---|---|
| 桌面应用操作 | [Umbriel](https://github.com/ObscuritySRL/umbriel) | 任意 Windows 桌面程序，含最小化与被遮挡窗口 |
| 浏览器操作 | [Playwright MCP](https://github.com/microsoft/playwright-mcp) | 无头 Edge / Chromium 实例 |

两者均以 **MCP（Model Context Protocol）** 标准接入 DSH，无需修改 DSH 源码。

---

## 2. 设计取舍

### 2.1 视觉定位方案的固有问题

现有方案多采用**屏幕截图 + 像素坐标定位**：截取屏幕画面，交由模型估计目标控件坐标，再在该坐标处派发鼠标事件。该方案实现直接、对被操作程序无要求，但存在三类问题：

1. **定位不确定性**——坐标为估计值，控件位置微调或渲染差异即可导致误击；
2. **无法处理不可见窗口**——画面中不存在的窗口无法定位，最小化或被其他窗口遮挡时即失效；
3. **上下文成本高**——图像 token 消耗显著高于等价的结构化文本。

### 2.2 本模板的方案

Windows 应用通过 **UI Automation（UIA）** 向系统暴露其界面结构：控件类型、可访问名称、当前值、启用状态与边界。该结构的设计用途是支撑辅助技术（屏幕阅读器），但其信息密度与确定性同样适合作为 Agent 的操作通道。

采用该通道带来的直接结果：

- 定位基于**控件标识**而非像素估计；
- 可操作**尚未渲染到屏幕**的窗口；
- 每次操作返回新的结构化快照，元素引用（ref）带代际标识——**过期引用会被明确拒绝，而不会静默作用于错误目标**。

### 2.3 回退策略

不暴露 UIA 结构的程序（典型为全屏 DirectX 渲染的应用，如游戏）无法使用上述通道。本模板保留视觉路径作为回退：窗口截图、GPU 合成画面捕获、OCR 与模板匹配。回退路径的可靠性取决于具体应用，不属于本模板的能力保证范围。

---

## 3. 架构

```
用户指令
   │
   ▼
DSH Agent Loop
   │
   ▼
MCP 工具注册表
   │
   ├── mcp__umbriel__*      ──▶  Umbriel        ──▶  UI Automation / Win32
   │                                                  （无光标输入路由）
   │
   └── mcp__playwright__*   ──▶  Playwright MCP ──▶  无头 Chromium / Edge
```

Umbriel 通过 Windows 消息与 UI Automation 模式向目标窗口派发输入，而非移动真实光标，因此操作过程中用户的鼠标位置与键盘焦点不变。

---

## 4. 能力范围

### 4.1 支持

| 能力 | 说明 |
|---|---|
| 桌面应用操作 | 点击、文本输入、取值、勾选、列表选择、滚动；支持最小化、被遮挡与后台窗口 |
| 界面读取 | 结构化快照、数据表格、文本内容、控件状态与边界 |
| 系统信息查询 | 进程、服务、网络连接、事件日志、磁盘、计划任务、防火墙规则（无需调用 shell） |
| 窗口管理 | 移动、缩放、最小化、置顶、贴靠、透明度调整 |
| 浏览器自动化 | 无头浏览器加载、导航、表单填写与内容提取 |
| 视觉回退 | 窗口截图、被遮挡窗口捕获、OCR、颜色与图像匹配 |

### 4.2 限制

| 限制 | 原因 |
|---|---|
| 无法操作高完整性（管理员权限）窗口 | UIPI 隔离机制：普通完整性进程不得向高完整性窗口派发输入 |
| 部分控件操作时会短暂抢占前台 | 无独立窗口句柄（HWND）的控件（WinUI / WPF / Electron 中常见）仅提供 UI Automation 模式，经由 MSAA 桥接时需先激活目标。工具会在结果中标记该情况 |
| 全屏 DirectX 应用无结构可读 | 此类程序不暴露 UIA 树，仅能走视觉回退路径 |

> 上述限制源于平台机制，非配置问题。表内第二项可通过优先选用基于 `Invoke` / `Value` / `Toggle` 模式的操作来降低触发频率。

---

## 5. 环境要求

| 依赖 | 要求 | 检查方式 |
|---|---|---|
| 操作系统 | Windows 10 / 11 | — |
| Node.js | ≥ 20 | `node --version` |
| DSH | 0.2.x | 可正常启动 |
| 网络代理 | 可选 | 用于访问外部网络；若使用，需知悉其监听端口 |

---

## 6. 安装

### 6.1 一键安装

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

### 6.2 手动安装

```powershell
# 1. 安装 Bun 运行时
npm i -g bun

# 2. 安装 Umbriel
bun add -g umbriel

# 3. 安装 Playwright MCP
npm i -g @playwright/mcp

# 4. 下载浏览器内核
#    注意：必须使用 @playwright/mcp 自带的 Playwright 下载，
#    以保证内核版本与其运行时预期一致。
node "$env:APPDATA\npm\node_modules\@playwright\mcp\node_modules\playwright\cli.js" install chromium
```

---

## 7. 配置

### 7.1 写入位置

配置文件位于 DSH 的 profile 目录下：

```
~\.dsh\profiles\<profile 名>\cordis.patch.yml
```

DSH 桌面版通常为 `desktop`，Web 版通常为 `web`。可查看 `~\.dsh\profiles\` 下存在哪些目录以确认。

### 7.2 配置内容

将 [`cordis.patch.yml.example`](./cordis.patch.yml.example) 中的 `- insert:` 段落追加至该文件末尾。

配置采用“补丁层”语义，顶层条目有两种含义：

| 写法 | 含义 |
|---|---|
| `- id: <已存在条目的 id>` | 覆盖该条目的配置 |
| `- insert: [...]` | **新增**条目 |

> 若将新条目直接写作顶层 `- id: ...`，加载器会查找同名已有条目；查找失败时**静默跳过，不产生任何错误提示**。新增条目必须置于 `insert` 列表内。

### 7.3 需要修改的字段

| 字段 | 说明 | 获取方式 |
|---|---|---|
| `command`（playwright） | `node.exe` 的绝对路径 | `(Get-Command node).Source` |
| `args[0]`（playwright） | `@playwright/mcp` 的 `cli.js` 路径 | 通常为 `%APPDATA%\npm\node_modules\@playwright\mcp\cli.js` |
| `<用户名>`（两处） | 当前用户目录名 | `$env:USERNAME` |
| `--proxy-server` | 代理监听地址 | 无需代理时删除该参数及其值 |

### 7.4 生效方式

保存后 DSH 会**热重载**该配置，通常在 1 分钟内生效，无需重启。

---

## 8. 验证

在 DSH 会话中依次执行以下指令：

**验证桌面操作通道**

> 列出当前所有窗口

预期返回窗口列表，包含窗口句柄、所属进程与是否最小化。

**验证浏览器通道**

> 用 playwright 打开 https://example.com 并返回页面标题

预期返回 `Example Domain`，且**桌面不出现任何浏览器窗口**。

---

## 9. 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 配置已写入，但工具未出现且无报错 | 新增条目写在了顶层而非 `insert` 列表内，被静默跳过 | 参照 [7.2 节](#72-配置内容) 调整写法 |
| `Chromium distribution 'chrome' is not found` | Playwright MCP 默认查找系统 Chrome | 增加 `--browser msedge`；已安装 Chrome 时无需该参数 |
| 无头浏览器无法访问外部网络 | MCP 默认不使用系统代理 | 增加 `--proxy-server http://127.0.0.1:<端口>` |
| Umbriel 退出码 255，提示 `bun is not installed in %PATH%` | `~/.bun/bin/umbriel.exe` 为启动壳，运行时需要 `bun` 位于 `PATH` | 改为由 `bun.exe` 直接执行 `umbriel/mcp.ts` |
| 运行时重新下载浏览器内核 | 使用了系统全局的 Playwright 下载内核，版本与 MCP 预期不符 | 改用 `@playwright/mcp` 自带的 Playwright（见 [6.2 节](#62-手动安装) 第 4 步） |
| 某次操作导致前台窗口切换 | 目标控件无独立窗口句柄，只能经由需要激活的 UI Automation 通道 | 平台限制，无法规避；工具会在结果中标记，可据此替换为无光标动作 |

---

## 10. 文件说明

| 文件 | 用途 |
|---|---|
| `README.md` | 本文档 |
| `LICENSE` | MIT 许可协议 |
| `install.ps1` | 依赖一键安装脚本 |
| `cordis.patch.yml.example` | DSH 配置片段，需追加至 `cordis.patch.yml` |
| `SKILL.md` | 供 Agent 读取的操作规范：工具选型、引用语义、触发条件说明 |

---

## 11. 术语表

| 术语 | 定义 |
|---|---|
| **Computer-Use Agent** | 能够观察并操作图形界面以完成任务的智能体 |
| **UI Automation (UIA)** | Windows 提供的界面结构访问接口，供辅助技术与自动化程序读取控件树 |
| **无障碍树** | 应用通过 UIA 暴露的界面结构，包含控件的类型、名称、状态与位置 |
| **HWND** | Windows 为窗口分配的句柄。控件是否拥有独立 HWND 决定其可用的输入派发方式 |
| **UIPI** | 用户界面权限隔离，阻止低完整性进程向高完整性窗口派发输入 |
| **焦点** | 当前接收键盘输入的窗口或控件 |
| **MCP** | Model Context Protocol，用于向模型暴露外部工具的标准协议 |
| **stdio 传输** | MCP 的一种传输方式，客户端以子进程形式启动服务器，经标准输入输出通信 |
| **无头模式** | 浏览器不创建可见窗口的运行方式 |
| **热重载** | 配置文件变更后由程序自动重新加载，无需重启进程 |
| **OCR** | 从图像中识别文字 |
| **ref（元素引用）** | 界面快照中某个控件的标识符，带代际编号；仅对生成它的快照有效 |

---

## 12. 许可

本项目采用 [MIT 许可协议](./LICENSE)。

---

## 致谢

- [Umbriel](https://github.com/ObscuritySRL/umbriel) —— Windows 后台桌面控制
- [Playwright MCP](https://github.com/microsoft/playwright-mcp) —— 浏览器自动化
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) —— 提供 MCP 客户端与插件机制
- DeepSeek-V4.1-Flash —— 协助想法落地与技术验证

---

## 声明

本仓库代码由 AI 编写并提供，已在 Windows 11 + DSH 0.2.x 环境下实际验证。欢迎通过 Issue 反馈问题或改进建议。
