[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo")]
    [string] $Config = "Release",

    [string] $BuildDir = "build-vulkan",

    [int] $Jobs = 0,

    [switch] $Clean
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path $PSScriptRoot -Parent
$buildPath = Join-Path $repoRoot $BuildDir

function Find-CMake {
    $command = Get-Command cmake -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installPath) {
            $candidate = Join-Path $installPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    throw "CMake was not found. Install CMake or Visual Studio with the Desktop development with C++ workload."
}

function Set-VulkanSdk {
    if ($env:VULKAN_SDK -and (Test-Path (Join-Path $env:VULKAN_SDK "Bin\glslc.exe"))) {
        return
    }

    $sdkRoots = @(
        "C:\VulkanSDK",
        (Join-Path $env:ProgramFiles "VulkanSDK")
    )
    foreach ($sdkRoot in $sdkRoots) {
        if (-not (Test-Path $sdkRoot)) {
            continue
        }

        $sdk = Get-ChildItem $sdkRoot -Directory |
            Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending |
            Select-Object -First 1
        if ($sdk -and (Test-Path (Join-Path $sdk.FullName "Bin\glslc.exe"))) {
            $env:VULKAN_SDK = $sdk.FullName
            $env:Path = "$(Join-Path $sdk.FullName 'Bin');$env:Path"
            return
        }
    }

    throw "The Vulkan SDK was not found. Install the LunarG Vulkan SDK with the default options."
}

try {
    $cmake = Find-CMake
    Set-VulkanSdk

    if ($Clean -and (Test-Path $buildPath)) {
        Write-Host "Removing $buildPath"
        Remove-Item -LiteralPath $buildPath -Recurse -Force
    }

    Write-Host "Configuring llama.cpp ($Config, Vulkan SDK $env:VULKAN_SDK)"
    & $cmake -S $repoRoot -B $buildPath -DGGML_VULKAN=ON
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed with exit code $LASTEXITCODE."
    }

    $buildArgs = @("--build", $buildPath, "--config", $Config, "--parallel")
    if ($Jobs -gt 0) {
        $buildArgs += $Jobs
    }

    Write-Host "Building llama.cpp"
    & $cmake @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE."
    }

    $binCandidates = @(
        (Join-Path $buildPath "bin\$Config"),
        (Join-Path $buildPath "bin")
    )
    $binPath = $binCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    Write-Host "Build complete: $binPath" -ForegroundColor Green
}
catch {
    Write-Error $_
    exit 1
}
