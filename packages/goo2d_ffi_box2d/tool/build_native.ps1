# Builds the native library for the HOST platform only, for use by
# `flutter test`, `dart run` and tool/ scripts.
#
# A real Flutter application never needs this: the goo2d_ffi_box2d plugin
# compiles and bundles the library as part of the app build. But the test
# runner and standalone scripts do not build plugins, so without this there
# is no library for lib/src/library.dart to find.
#
# Precedent for a tool/ script that has to be run by hand before certain
# tests: goo/tool/ring_buffer_stress.dart.
#
#   powershell -File tool/build_native.ps1               # release
#   powershell -File tool/build_native.ps1 -DebugBuild   # for a native debugger
#   powershell -File tool/build_native.ps1 -Clean        # discard the build tree
#
# `-DebugBuild`, not `-Debug`: CmdletBinding already defines `-Debug` as a
# common parameter, and redeclaring it makes PowerShell refuse to load the
# script at all.

[CmdletBinding()]
param(
  [switch]$DebugBuild,
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $packageRoot 'src'
# Matches the layout lib/src/library.dart searches for: build/<host os>.
$buildDir = Join-Path $packageRoot 'build/windows'
$config = if ($DebugBuild) { 'Debug' } else { 'Release' }

if (-not (Test-Path (Join-Path $sourceDir 'box2d/src'))) {
  throw "Vendored Box2D not found at $sourceDir/box2d/src."
}

if ($Clean -and (Test-Path $buildDir)) {
  Write-Host "Removing $buildDir"
  Remove-Item -Recurse -Force $buildDir
}

# CMake picks a Visual Studio generator only for VS versions it knows about.
# CMake 3.31 tops out at "Visual Studio 17 2022", so a newer VS (2026 = v18)
# makes it silently fall back to "NMake Makefiles" and then fail with
# CMAKE_C_COMPILER not set. Loading vcvars64.bat puts cl.exe on PATH, which
# makes the NMake generator work regardless of how new the toolchain is -
# and keeps this script working when CMake and VS are upgraded out of step.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path $vswhere)) {
  throw 'vswhere.exe not found - Visual Studio with the C++ workload is required.'
}

$vsPath = & $vswhere -latest -products * `
  -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  -property installationPath
if (-not $vsPath) {
  throw 'No Visual Studio installation with the C++ build tools was found.'
}

$vcvars = Join-Path $vsPath 'VC/Auxiliary/Build/vcvars64.bat'
if (-not (Test-Path $vcvars)) {
  throw "vcvars64.bat not found at $vcvars"
}

Write-Host "Visual Studio: $vsPath"
Write-Host "Configuration: $config"

# One cmd.exe invocation: the environment vcvars64 sets does not survive
# back into PowerShell, so configure and build have to happen inside it.
$configure = "cmake -S `"$sourceDir`" -B `"$buildDir`" -G `"NMake Makefiles`" -DCMAKE_BUILD_TYPE=$config"
$build = "cmake --build `"$buildDir`""
$command = "`"$vcvars`" >nul 2>&1 && $configure && $build"

& cmd /c $command
if ($LASTEXITCODE -ne 0) {
  throw "Native build failed with exit code $LASTEXITCODE"
}

$dll = Join-Path $buildDir 'goo2d_box2d.dll'
if (-not (Test-Path $dll)) {
  throw "Build reported success but $dll is missing."
}

$sizeKb = [math]::Round((Get-Item $dll).Length / 1KB)
Write-Host ""
Write-Host "Built $dll ($sizeKb KB)"
