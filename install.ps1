#Requires -Version 5.1
<#
    dsh-background-computer-use —— 依赖一键安装

    用法（在 PowerShell 里，于本文件夹下执行）：
        powershell -ExecutionPolicy Bypass -File install.ps1

    它会依次做四件事：
        1. 检查 Node.js
        2. 安装 Bun（umbriel 的运行时）
        3. 安装 umbriel 和 @playwright/mcp
        4. 用「与 @playwright/mcp 匹配的那套 playwright」下载 Chromium

    每一步都会先告诉你要干什么。失败会停下来并说明原因。
#>

$ErrorActionPreference = 'Stop'

function Step($n, $t) { Write-Host "`n=== [$n] $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [OK] $m"   -ForegroundColor Green }
function Bad($m)  { Write-Host "  [!!] $m"   -ForegroundColor Red }

# ---------------------------------------------------------------- 0. Node.js
Step 0 '检查 Node.js'
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Bad '没找到 node。请先安装 Node.js 20 或更高版本：https://nodejs.org/'
    exit 1
}
Ok ("node " + (node --version))

# ------------------------------------------------------------------- 1. Bun
Step 1 '安装 Bun（umbriel 的运行时）'
$bunExe = $null

function Resolve-Bun {
    $c = Get-Command bun -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $p = Join-Path $env:APPDATA 'npm\node_modules\bun\bin\bun.exe'
    if (Test-Path $p) { return $p }
    return $null
}

$bunExe = Resolve-Bun
if ($bunExe) {
    Ok "已装 bun ($bunExe)"
} else {
    Write-Host '  执行: npm i -g bun'
    npm i -g bun
    $bunExe = Resolve-Bun
    if (-not $bunExe) { Bad '装完仍找不到 bun，请重开一个终端再跑本脚本。'; exit 1 }
    Ok "已装 bun"
}

# --------------------------------------------------------------- 2. umbriel
Step 2 '安装 umbriel'
Write-Host "  执行: $bunExe add -g umbriel"
& $bunExe add -g umbriel
$umb = Join-Path $env:USERPROFILE '.bun\install\global\node_modules\umbriel\mcp.ts'
if (Test-Path $umb) { Ok "umbriel 就位: $umb" }
else { Bad "没找到 $umb，安装可能没成功。"; exit 1 }
Write-Host '  注意：~/.bun/bin/umbriel.exe 只是个启动壳，运行时需要 bun 在 PATH；' -ForegroundColor DarkGray
Write-Host '        所以 DSH 配置里我们直接用 bun 跑入口文件。' -ForegroundColor DarkGray

# -------------------------------------------------------- 3. @playwright/mcp
Step 3 '安装 @playwright/mcp'
Write-Host '  执行: npm i -g @playwright/mcp'
npm i -g @playwright/mcp
$mcpCli = Join-Path $env:APPDATA 'npm\node_modules\@playwright\mcp\cli.js'
if (Test-Path $mcpCli) { Ok "就位: $mcpCli" } else { Bad "没找到 $mcpCli"; exit 1 }

# ------------------------------------- 4. 下载「版本匹配」的 Chromium 内核
Step 4 '下载 Chromium（约 120MB，第一次会慢一点）'
# 关键：要用 @playwright/mcp **自己带的那套** playwright 来下载，
# 否则版本号对不上，运行时它还会再下一次（而且可能失败）。
$ownCli = Join-Path $env:APPDATA 'npm\node_modules\@playwright\mcp\node_modules\playwright\cli.js'
if (-not (Test-Path $ownCli)) {
    Bad "没找到 $ownCli"
    Write-Host '  @playwright/mcp 的结构可能变了；退而求其次可以用: npx -y playwright install chromium'
    exit 1
}
Write-Host "  执行: node `"$ownCli`" install chromium"
node $ownCli install chromium

# --------------------------------------------------------------------- 完成
Write-Host "`n全部完成。" -ForegroundColor Green
Write-Host @'

下一步：把配置写进 DSH
  1. 打开   ~\.dsh\profiles\<profile 名>\cordis.patch.yml
  2. 把本文件夹里 cordis.patch.yml.example 的 `- insert:` 那段追加到末尾
  3. 把里面的三处改成你自己的：
       - node.exe 绝对路径      →  PowerShell 里跑：(Get-Command node).Source
       - <用户名>               →  PowerShell 里跑：$env:USERNAME
       - 代理端口（不需要就删掉那两行 --proxy-server）
  4. 保存。DSH 会自动热重载，约 1 分钟内生效，不用重启。

怎么确认成功：
  - 问 AI「列出当前所有窗口」→ 应该返回窗口列表（含 hWnd、进程名、是否最小化）
  - 问 AI「用 playwright 打开 example.com 告诉我标题」→ 应该返回 Example Domain，
    而且桌面上不会出现任何浏览器窗口
'@
