<#
.SYNOPSIS
Automates the installation of all required dependencies and compilation of Hyprland and its related components on Debian sid.

.DESCRIPTION
This PowerShell script streamlines the setup process for Hyprland on Debian sid by performing the following tasks:

- Verifies the presence of essential tools like `sudo` and `git`
- Installs all required system packages and development libraries via `apt-get`
- Clones and builds multiple Hyprland-related repositories from GitHub
- Applies appropriate build systems (Meson, CMake, Make) based on each repository
- Installs compiled binaries using `sudo`
- Logs all output to a timestamped log file for review and debugging
- Cleans up temporary build directories after completion

The script is designed to be idempotent and safe to re-run. It provides detailed console output and error handling to assist users during installation. All operations requiring elevated privileges are clearly marked and executed via `sudo`.

Note: This script is intended for advanced users familiar with Debian sid and Hyprland's architecture.

.LINK
https://github.com/Endredaol/Install-Scripts
#>

Set-StrictMode -Version Latest

$logFilePath = Join-Path $PSScriptRoot "hyprland-install-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-Host "Welcome to the Hyprland Dependency & Compilation Installer for Debian sid" -ForegroundColor Green
Write-Host "This script will automatically install all dependencies and compile/install Hyprland"
Write-Host "All detailed logs will be recorded to: $logFilePath"
Write-Host "Please note that this log file will not be automatically deleted after completion"
Write-Host ""

Start-Transcript -Path $logFilePath -Append -Force

try
{
	Write-Host "Running pre-inspection..." -ForegroundColor Yellow
	if (-not (Get-Command sudo -ErrorAction SilentlyContinue)) 
	{ throw "sudo command not found. Please ensure sudo is installed on your system and the current user has execution permissions" }

	if (-not (Get-Command git  -ErrorAction SilentlyContinue)) 
	{ throw "git command not found. Please install git first" }

	Write-Host "Pre-inspection cleared" -ForegroundColor Green
	Write-Host ""
}
catch
{
	Write-Error $_
	exit 1
}

$packages = @(
	"cmake", "meson", "ninja-build", "pkg-config",
	
	"libdisplay-info-dev", "libdrm-dev", "libgbm-dev", "libgl1-mesa-dev", "libgles-dev", "libglaze-dev", "libinput-dev", 
	"libpipewire-0.3-dev", "libsdbus-c++-dev", "libwayland-dev", "libxcursor-dev", "libxkbcommon-dev", "qt6-base-dev",
	"qt6-declarative-dev", "qt6-declarative-private-dev", "qt6-wayland-dev", "qt6-wayland-private-dev", "wayland-protocols",
	
	"hwdata", "libcairo2-dev", "libmagic-dev", "libpixman-1-dev", "libpugixml-dev", "libre2-dev",
	"librsvg2-dev", "libseat-dev", "libtomlplusplus-dev", "libudis86-dev", "libzip-dev",

	"pipewire", "pipewire-pulse",
	
	"libxcb-composite0-dev", "libxcb-errors-dev", "libxcb-icccm4-dev", "libxcb-res0-dev", "libxcb-xfixes0-dev",
	
	"emacs-pgtk", "fonts-noto-cjk", "kitty", "mako-notifier", "obs-studio", "tofi", "udisks2", "waybar", "xdg-desktop-portal",
	"lsb-release", "software-properties-common"
)

$hyprland_build_dir = "hyprland-build"
if (Test-Path $hyprland_build_dir)
{
	Write-Host "Old build directory detected, cleaning up..." -ForegroundColor Yellow
	Remove-Item $hyprland_build_dir -Recurse -Force
}
New-Item -ItemType Directory -Name $hyprland_build_dir | Out-Null
Set-Location $hyprland_build_dir

$repositories = @(
	"hyprland-protocols",
	"hyprwayland-scanner",
	"hyprutils",
	"hyprland-qtutils",
	"hyprlang",
	"xdg-desktop-portal-hyprland",
	"hyprgraphics",
	"hyprcursor",
	"aquamarine",
	"Hyprland"
)

function Build-Repository
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$repoName
	)

	Write-Host ("-" * ($Host.UI.RawUI.WindowSize.Width)) -ForegroundColor Cyan
	Write-Host "Processing repository: $repoName" -ForegroundColor Yellow
	Write-Host ("-" * ($Host.UI.RawUI.WindowSize.Width)) -ForegroundColor Cyan

	try
	{
		Write-Host "-> Cloning repo..."
		git clone --depth=1 "https://github.com/hyprwm/$repoName"
		if ($LASTEXITCODE -ne 0) { throw "Clone failed for $repoName" }
		Set-Location $repoName

		Write-Host "-> Configuring & building..."
		
		switch ($repoName)
		{
			"hyprland-protocols"
			{
				Write-Host "-> Configuring and building with Meson"
				meson setup build
				if ($LASTEXITCODE -ne 0) { throw "meson setup failed" }
			}
			"hyprwayland-scanner"
			{
				Write-Host "-> Using hyprwayland-scanner specific cmake command"
				cmake -DCMAKE_INSTALL_PREFIX=/usr -B build
				if ($LASTEXITCODE -ne 0) { throw "cmake configuration failed" }
				cmake --build build --config Release -j $nproc
			}
			"xdg-desktop-portal-hyprland"
			{
				Write-Host "-> Building xdg-desktop-portal-hyprland with specific cmake flags"
				cmake -DCMAKE_INSTALL_LIBEXECDIR=/usr/lib -DCMAKE_INSTALL_PREFIX=/usr -B build
				if ($LASTEXITCODE -ne 0) { throw "cmake configuration failed" }
				cmake --build build --config Release -j $nproc
			}
			"Hyprland"
			{
				Write-Host "-> Building with make command"
				make all -j $nproc
			}
			default
			{
				Write-Host "-> Using standard cmake command"
				cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr -S . -B ./build
				if ($LASTEXITCODE -ne 0) { throw "cmake configuration failed" }
				cmake --build ./build --config Release --target all -j $nproc
			}
		}
		
		if ($LASTEXITCODE -ne 0) { throw "Compilation of $repoName failed. Please check the error messages" }

		Write-Host "-> Installing... (sudo privileges required)"
		
		switch ($repoName)
		{
			"hyprland-protocols" { sudo meson   install -C build }
			"Hyprland"           { sudo make    install }
			default              { sudo cmake --install build }
		}

		if ($LASTEXITCODE -ne 0) { throw "Installation of $repoName failed" }

		Write-Host "Repository $repoName has been successfully compiled and installed" -ForegroundColor Green
	}
	catch
	{
		Write-Error "An error occurred while processing $repoName : $_"
		Set-Location ..
		exit 1
	}
	
	Set-Location ..
}

try
{
	Write-Host "Updating package list... (sudo privileges required)" -ForegroundColor Yellow
	sudo apt-get update

	if ($LASTEXITCODE -ne 0) { throw "'apt-get update' failed. Please check your network connection and repository configuration" }
	
	Write-Host "Package list updated successfully" -ForegroundColor Green
	Write-Host ""

	Write-Host "Preparing to install the following dependency packages: " -ForegroundColor Yellow
	$packages | ForEach-Object { Write-Host " - $_" }
	Write-Host ""
	Write-Host "The installation process may take some time, please wait patiently..." -ForegroundColor Yellow

	& sudo apt-get install -y -- $packages

	if ($LASTEXITCODE -ne 0) { throw "Some or all package installations failed. Please check the apt-get output above to identify the issue" }
	Write-Host ""
	Write-Host "All dependencies have been successfully installed!" -ForegroundColor Green

	$nproc = (nproc)

	foreach ($repo in $repositories) { Build-Repository -repoName $repo }

	Write-Host ("-" * ($Host.UI.RawUI.WindowSize.Width)) -ForegroundColor Green
	Write-Host "Congratulations! Hyprland and all its related components have been successfully compiled and installed!" -ForegroundColor Green
	Write-Host "You can now configure Hyprland and start it" -ForegroundColor Green
}
catch
{
	Write-Error "A fatal error occurred during script execution: $_"
	exit 1
}
finally
{
	Stop-Transcript
	
	Write-Host ""

	Write-Host "Cleaning up build directory..." -ForegroundColor Yellow
	Set-Location ..
	Remove-Item $hyprland_build_dir -Recurse -Force
	Write-Host "Cleanup completed" -ForegroundColor Green
}
