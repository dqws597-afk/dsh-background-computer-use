# dsh-background-computer-use

给 **DeepSeek Harness (DSH)** 加上「**后台操作**」能力：让 AI 在你继续用电脑的同时，悄悄操作 Windows 桌面应用和浏览器——**不抢你的键盘焦点、不移动你的鼠标、不弹出窗口**。

---

## 它和常见的 Computer Use 有什么不同

主流的 Computer Use（比如 Claude 的电脑操作、各种截图方案）走的是**视觉路线**：

> 给 AI 拍一张屏幕截图 → 问它"登录按钮在哪" → 它回答"大概在像素坐标 (800, 450)" → 程序在那儿戳一下。
>
> **像闭着眼睛看着照片去戳按钮**：会看错、会点偏、图片还很贵（图片比文字贵得多）。

这套走的是**无障碍树路线**：

> 其实每个 Windows 软件都**主动提供了一份"界面目录"**——里面写着"我这儿有个按钮，名字叫『登录』，位置在左上方，可以按"。这份目录原本是**做给读屏软件用的**（盲人用的那种）。
>
> AI 直接读目录，就能精确地操作"那个叫『登录』的按钮"。
>
> **像直接翻说明书，而不是猜照片。**

带来的实际好处：

- 定位是**精确**的，不是"大概在这个像素"
- 能操作**最小化、被遮挡、在后台**的窗口
- 每步操作都返回新的界面快照，引用（ref）带版本号，**过期的引用会被明确拒绝，而不是点到别的地方去**
- 省 token（结构化文本 vs 截图）

---

## 能做什么 / 做不到什么

**能做：**

- 操作任意桌面应用，包括最小化 / 被遮挡 / 后台的窗口
- 不移动你的鼠标指针，不切断你的键盘焦点
- 读窗口内容：无障碍树、表格、OCR（把图里的字读出来）
- 系统诊断：进程、服务、网络连接、事件日志、磁盘、防火墙——**不需要开 shell**
- 浏览器自动化：无头 Edge 后台抓页面
- 窗口管理：移动 / 最小化 / 置顶 / 半屏吸附 / 改透明度

**做不到（诚实版）：**

| 限制 | 说明 |
|---|---|
| 有 **UIPI 墙**的窗口碰不了 | UIPI 是 Windows 的安全隔离：普通权限的程序不许操作管理员权限的程序（比如任务管理器、部分游戏平台）。这是设计，不是 bug |
| 部分现代控件**仍会短暂抢前台** | 没有独立窗口句柄的控件（WinUI / WPF / Electron 里常见的那些）只能走"必须先激活"的通道。好消息是工具会**明确告诉你哪一步抢了**（结果里带 `⚠`），不会偷偷抢 |
| 全屏 DirectX 游戏读不到结构 | 这类应用不提供界面目录，会退化到 OCR / 像素匹配，成功率看具体游戏 |

---

## 名词表

| 词 | 大白话 |
|---|---|
| **无障碍树 / a11y tree** | 软件提供给读屏软件的"界面目录"，列出每个控件的名字和位置。`a11y` 是 accessibility 的缩写（a + 11 个字母 + y） |
| **UIA / UI Automation** | 微软官方的"读这份目录"的接口 |
| **焦点 / focus** | 当前在听你键盘的那个窗口。焦点被抢 = 你打的字跑到别的窗口去了 |
| **HWND / 窗口句柄** | Windows 给每个窗口发的"身份证号" |
| **投递消息 / posted message** | 不真动鼠标，而是给窗口塞张纸条说"有人按了你一下"——这是"后台点击"的原理 |
| **UIPI 墙** | Windows 的权限隔离，普通程序不能操作管理员程序 |
| **MCP** | Model Context Protocol，一个**统一插座标准**：规定"给 AI 用的工具该怎么插上来、AI 该怎么调用"。有了它，同一个工具能插到 Claude / Cursor / DSH 等不同客户端上 |
| **无头浏览器 / headless** | 一个**没有窗口**的浏览器，在后台默默打开网页 |
| **OCR** | 把图片里的字读出来变成文本 |
| **热重载 / hot reload** | 改完配置文件**不用重启**软件，它自己会重新加载 |

---

## 前置条件

| 依赖 | 要求 | 怎么检查 |
|---|---|---|
| Windows | 10 / 11 | — |
| Node.js | ≥ 20 | `node --version` |
| DSH | 0.2.x，能正常启动 | — |
| 代理（可选） | 访问外网用 | 配置里要写端口，不需要就删掉那两行 |

## 安装

### 懒人版

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

### 手动版（想看每一步在干什么）

```powershell
# 1. 装 Bun（umbriel 的运行时）
npm i -g bun

# 2. 装 umbriel（Windows 后台桌面控制）
bun add -g umbriel

# 3. 装 Playwright MCP
npm i -g @playwright/mcp

# 4. 下载 Chromium
#    注意：必须用 @playwright/mcp **自带的那套** playwright 来下载，
#    否则版本号对不上，运行时它会再去下一次（而且可能失败）。
node "$env:APPDATA\npm\node_modules\@playwright\mcp\node_modules\playwright\cli.js" install chromium
```

## 写配置

打开 `~\.dsh\profiles\<你的 profile 名>\cordis.patch.yml`，把 [`cordis.patch.yml.example`](./cordis.patch.yml.example) 里的 `- insert:` 那段**追加到文件末尾**，然后改三处：

1. `node.exe` 的绝对路径（`(Get-Command node).Source`）
2. 两处 `<用户名>`（`$env:USERNAME`）
3. 代理端口（不需要代理就删掉 `--proxy-server` 那两行）

**保存后 DSH 会热重载，不用重启**（实测约 1 分钟内生效）。

## 验证

在 DSH 里对 AI 说：

> 列出当前所有窗口

应该返回一份窗口列表，带窗口句柄、进程名、是否最小化。

> 用 playwright 打开 https://example.com 告诉我标题

应该返回 `Example Domain`，而且**桌面上不会出现任何浏览器窗口**。

---

## 踩过的坑（都是实测出来的）

| 现象 | 原因 | 解决 |
|---|---|---|
| 配置写了，但工具就是不出现，**也不报错** | `cordis.patch.yml` 是「补丁层」：顶层 `- id:` 的意思是"覆盖**已存在**的同 id 条目"，id 不存在就被**静默忽略** | 新增条目必须写成 `- insert:` 列表 |
| `Chromium distribution 'chrome' is not found` | Playwright MCP 默认去找系统 Chrome | 加 `--browser msedge`（装了 Chrome 就不需要） |
| 无头浏览器打不开外网 | MCP 默认**不走系统代理** | 加 `--proxy-server http://127.0.0.1:<端口>` |
| umbriel 退出码 255，报 `bun is not installed in %PATH%` | `~/.bun/bin/umbriel.exe` 只是个 8KB 的**启动壳**，它需要 bun 在 PATH 里 | 用 `bun.exe` 直接跑 `umbriel/mcp.ts` |
| 浏览器内核版本对不上，运行时又去下载 | 用了系统全局的 playwright 下载内核 | 用 `@playwright/mcp` 自带的 playwright CLI（见安装第 4 步） |
| 操作时前台被抢了一下 | 该控件没有独立窗口句柄，只能走激活通道 | 无解（平台限制）；工具会在结果里用 `⚠` 标出来，你可以据此判断 |

---

## 附带：给 AI 的操作纪律

[`SKILL.md`](./SKILL.md) 是写给 AI 看的"工具选择与操作纪律"——哪套工具干什么用、ref 怎么用、哪些动作会抢焦点。

放到 `~\.dsh\skills\background-computer-use\SKILL.md` 就会自动出现在 AI 的技能目录里（DSH 会热加载，不用重启）。

---

## 目录结构

```
dsh-background-computer-use/
├── README.md                     ← 你正在看的这个
├── LICENSE                       ← MIT 协议
├── install.ps1                   ← 依赖一键安装
├── cordis.patch.yml.example      ← 要贴进 DSH 的配置片段
└── SKILL.md                      ← 给 AI 的操作纪律（可选但推荐）
```

---

## License

[MIT](./LICENSE) —— 随便用：改、商用、二次分发都行，只要保留版权声明，出了事别找我。
