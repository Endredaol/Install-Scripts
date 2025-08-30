<#
.SYNOPSIS
在 Debian 系 Linux 发行版上自动安装 Hyprland 及其所有相关组件的编译依赖项，并编译安装 Hyprland。

.DESCRIPTION
本脚本首先会更新软件包列表并安装所有必需的依赖包。
随后，它会自动克隆 Hyprland 及其所有相关库的 Git 仓库。
如果仓库已存在，则会尝试进行 git pull 操作以更新源代码。
所有详细的执行日志都将被重定向到一个临时日志文件中，以保持终端输出的整洁。

.EXAMPLE
pwsh -File ./install-hyprland-deps.ps1
#>
$black         = $PSStyle.Foreground.FromRgb('#0f0f14')
$red           = $PSStyle.Foreground.FromRgb('#f7768e')
$green         = $PSStyle.Foreground.FromRgb('#73daca')
$yellow        = $PSStyle.Foreground.FromRgb('#e0af68')
$blue          = $PSStyle.Foreground.FromRgb('#7aa2f7')
$magenta       = $PSStyle.Foreground.FromRgb('#bb9af7')
$cyan          = $PSStyle.Foreground.FromRgb('#7dcfff')
$white         = $PSStyle.Foreground.FromRgb('#c0caf5')

$brightBlack   = $PSStyle.Foreground.FromRgb('#414868')
$brightRed     = $PSStyle.Foreground.FromRgb('#f7768e')
$brightGreen   = $PSStyle.Foreground.FromRgb('#73daca')
$brightYellow  = $PSStyle.Foreground.FromRgb('#e0af68')
$brightBlue    = $PSStyle.Foreground.FromRgb('#7aa2f7')
$brightMagenta = $PSStyle.Foreground.FromRgb('#bb9af7')
$brightCyan    = $PSStyle.Foreground.FromRgb('#7dcfff')
$brightWhite   = $PSStyle.Foreground.FromRgb('#c0caf5')

# 强制使用严格模式，以捕获更多错误
Set-StrictMode -Version Latest

# 定义日志文件路径
$logFilePath = Join-Path $PSScriptRoot "hyprland-install-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# 欢迎信息
Write-Host "欢迎使用 Hyprland 依赖及编译安装脚本 for Debian/Ubuntu" -ForegroundColor Green
Write-Host "本脚本将自动完成所有依赖项的安装和 Hyprland 的编译安装。"
Write-Host "所有详细日志将被记录到文件: $logFilePath"
Write-Host "请注意，脚本完成后此文件不会自动删除。"
Write-Host ""

# 开始记录脚本的详细执行过程到日志文件
Start-Transcript -Path $logFilePath -Append -Force

# 检查是否已安装 sudo 和 git
try {
    Write-Host "正在进行预检查..." -ForegroundColor Yellow
    if (-not (Get-Command sudo -ErrorAction SilentlyContinue)) {
        throw "未找到 sudo 命令。请确保您的系统已安装 sudo，并且当前用户有权限执行。"
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "未找到 git 命令。请先安装 git。"
    }
    Write-Host "预检查通过。" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error $_
    exit 1
}

# 完整的依赖包列表，涵盖 Hyprland 及其所有子项目
$packages = @(
    # 通用构建工具
    "clang", "cmake", "ninja-build", "pkg-config",
    # Hyprland 核心依赖
    "libdisplay-info-dev", "libdrm-dev", "libgbm-dev", "libgl1-mesa-dev", "libgles-dev", "libinput-dev",
    "libwayland-dev", "libxcursor-dev", "libxkbcommon-dev", "wayland-protocols", 
    # Hyprland 扩展依赖
    "hwdata", "libcairo2-dev", "libmagic-dev", "libpixman-1-dev", "libpugixml-dev", "libre2-dev",
    "librsvg2-dev", "libseat-dev", "libtomlplusplus-dev", "libudis86-dev", "libzip-dev", 
    # Hyprland 的 xwayland 支持
    "libxcb-composite0-dev", "libxcb-errors-dev", "libxcb-icccm4-dev", "libxcb-res0-dev", "libxcb-xfixes0-dev",
    # 其他常用组件
    "emacs-pgtk", "kitty", "mako-notifier", "tofi", "waybar"
)

# 确保所有克隆的仓库都保存在一个临时目录中，方便后续清理
$hyprland_build_dir = "hyprland-build"
if (Test-Path $hyprland_build_dir) {
    Write-Host "找到旧的构建目录，正在移除..." -ForegroundColor Yellow
    Remove-Item $hyprland_build_dir -Recurse -Force
}
New-Item -ItemType Directory -Name $hyprland_build_dir | Out-Null
Set-Location $hyprland_build_dir

# Hyprland 及其相关库的 Git 仓库列表
$repositories = @(
    "hyprland-protocols",
    "hyprwayland-scanner",
    "hyprutils",
    "hyprlang",
    "hyprgraphics",
    "hyprcursor",
    "aquamarine",
    "Hyprland"
)

function Build-Repository {
    param(
        [Parameter(Mandatory = $true)]
        [string]$repoName
    )

    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "正在处理仓库: $repoName" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan

    try {
        # 1. 克隆或拉取仓库
        if (Test-Path $repoName) {
            Write-Host "-> 仓库已存在，正在执行 git pull..."
            Set-Location $repoName
            git pull
        }
        else {
            Write-Host "-> 正在克隆仓库..."
            git clone --depth=1 "https://github.com/hyprwm/$repoName"
            if ($LASTEXITCODE -ne 0) {
                throw "克隆 $repoName 失败。"
            }
            Set-Location $repoName
        }

        if ($LASTEXITCODE -ne 0) {
            throw "git pull 或 clone 操作失败。"
        }

        # 2. 编译
        Write-Host "-> 正在配置和编译..."
        
        # 根据仓库名称执行不同的编译命令
        switch ($repoName) {
            "hyprland-protocols" {
                 Write-Host "-> 使用 Meson 进行配置和编译"
                 meson setup build
                 if ($LASTEXITCODE -ne 0) { throw "meson setup 失败。" }
            }
            "hyprwayland-scanner" {
                Write-Host "-> 使用 hyprwayland-scanner 特定的 cmake 命令"
                cmake -DCMAKE_INSTALL_PREFIX=/usr -B build
                if ($LASTEXITCODE -ne 0) { throw "cmake 配置失败。" }
                cmake --build build --config Release -j $nproc
            }
            "Hyprland" {
                Write-Host "-> 使用 make 命令进行编译"
                make all -j $nproc
            }
            default {
                Write-Host "-> 使用标准 cmake 命令"
                cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr -S . -B ./build
                if ($LASTEXITCODE -ne 0) { throw "cmake 配置失败。" }
                cmake --build ./build --config Release --target all -j $nproc
            }
        }
        
        if ($LASTEXITCODE -ne 0) {
            throw "编译 $repoName 失败。请检查错误信息。"
        }

        # 3. 安装
        Write-Host "-> 正在安装... (需要 sudo 权限)"
        
        # 根据仓库名称执行不同的安装命令
        switch ($repoName) {
            "hyprland-protocols" {
                sudo meson install -C build
            }
            "Hyprland" {
                sudo make install
            }
            "hyprlang" {
                # hyprlang 的安装目录不同
                sudo cmake --install ./build
            }
            default {
                sudo cmake --install build
            }
        }

        if ($LASTEXITCODE -ne 0) {
            throw "安装 $repoName 失败。"
        }

        Write-Host "仓库 $repoName 已成功编译并安装。" -ForegroundColor Green
    }
    catch {
        Write-Error "在处理 $repoName 时发生错误: $_"
        Set-Location ..
        exit 1
    }
    
    # 返回到上一级目录
    Set-Location ..
}

# 脚本主程序
try {
    # Step 1: 更新软件包列表
    Write-Host "正在更新软件包列表... (需要 sudo 权限)" -ForegroundColor Yellow
    sudo apt-get update
    if ($LASTEXITCODE -ne 0) {
        throw "执行 'apt-get update' 失败，请检查您的网络连接和软件源配置。"
    }
    Write-Host "软件包列表更新成功。" -ForegroundColor Green
    Write-Host ""

    # Step 2: 安装依赖包
    Write-Host "准备安装以下依赖包：" -ForegroundColor Yellow
    $packages | ForEach-Object { Write-Host " - $_" }
    Write-Host ""
    Write-Host "安装过程可能需要一些时间，请耐心等待..." -ForegroundColor Yellow

    & sudo apt-get install -y -- $packages

    if ($LASTEXITCODE -ne 0) {
        throw "部分或全部软件包安装失败。请检查上面的 apt-get 输出信息以确定问题所在。"
    }
    Write-Host ""
    Write-Host "所有依赖项均已成功安装！" -ForegroundColor Green

    $nproc = (nproc)

    # Step 3: 克隆、编译和安装所有 Hyprland 相关的仓库
    foreach ($repo in $repositories) {
        Build-Repository -repoName $repo
    }

    Write-Host "--------------------------------------------------------" -ForegroundColor Green
    Write-Host "恭喜！Hyprland 及其所有相关组件已成功编译并安装！" -ForegroundColor Green
    Write-Host "您现在可以配置 Hyprland 并启动它了。" -ForegroundColor Green
}
catch {
    Write-Error "脚本执行过程中发生致命错误: $_"
    exit 1
}
finally {
    # 停止记录，并确保在终端上显示最终信息
    Stop-Transcript
    
    Write-Host ""
    # 无论成功或失败，都在脚本执行后清理构建目录
    Write-Host "正在清理构建目录..." -ForegroundColor Yellow
    Set-Location ..
    Remove-Item $hyprland_build_dir -Recurse -Force
    Write-Host "清理完成。" -ForegroundColor Green
}
