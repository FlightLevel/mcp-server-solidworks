<#
.SYNOPSIS
  Builds the SolidPilot Windows installer (.msi).

.DESCRIPTION
  1. Builds the C# execution server (Release) against the SolidWorks interop DLLs in -InteropDir.
  2. Stages the Python MCP adapter, cad-planner, the IR compiler and a private embedded Python
     runtime with all dependencies pre-installed (end users need no Python of their own).
  3. Packages everything with WiX Toolset 5 (restored from NuGet; nothing to install).

  Build machine needs: Visual Studio 2022 / Build Tools with the .NET desktop workload (MSBuild +
  .NET Framework 4.8 targeting pack), the .NET SDK (6 or newer, for WiX), Python 3.x with pip (only
  used to download wheels), and internet access. SolidWorks itself is NOT needed.

.EXAMPLE
  .\installer\build.ps1 -InteropDir C:\sw2024-interop -Version 1.0.0
#>
param(
    # Folder holding SolidWorks.Interop.sldworks.dll, .swconst.dll and .swpublished.dll
    # (copied from <SolidWorks 2024 install>\api\redist).
    [string]$InteropDir,

    # MSI version: major.minor.build (each part numeric; major/minor < 256).
    [string]$Version = '1.0.0',

    # Use an already-built execution server folder instead of building it (skips -InteropDir).
    [string]$ServerBinDir,

    [string]$PythonVersion = '3.13.14'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Pinned SHA-256 of python-<ver>-embed-amd64.zip from python.org. Add a line to use another version.
$PythonEmbedSha256 = @{
    '3.13.14' = '90b4e5b9898b72d744650524bff92377c367f44bd5fbd09e3148656c080ad907'
}

$repo      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outDir    = Join-Path $PSScriptRoot 'out'
$cacheDir  = Join-Path $PSScriptRoot 'cache'
$stageDir  = Join-Path $outDir 'stage'
$appDir    = Join-Path $stageDir 'app'

function Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Invoke-Checked([string]$exe, [string[]]$argList) {
    & $exe @argList
    if ($LASTEXITCODE -ne 0) { throw "'$exe $($argList -join ' ')' failed with exit code $LASTEXITCODE" }
}
# Copy a tree, skipping tests, caches, logs and private notes.
function Copy-Tree([string]$src, [string]$dst, [string[]]$excludeDirs = @(), [string[]]$excludeFiles = @()) {
    $skipDirs  = @('tests', '__pycache__', '.pytest_cache', '.solidpilot') + $excludeDirs
    $skipFiles = @('*.pyc', '*.log', '.env') + $excludeFiles
    Get-ChildItem $src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length).TrimStart('\')
        $parts = $rel.Split('\')
        if ($parts.Length -gt 1 -and ($parts[0..($parts.Length - 2)] | Where-Object { $skipDirs -contains $_ })) { return }
        foreach ($pat in $skipFiles) { if ($_.Name -like $pat) { return } }
        $target = Join-Path $dst $rel
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        Copy-Item $_.FullName $target
    }
}

if ($Version -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,5}$') { throw "Version must look like 1.2.3 (got '$Version')." }

# ---------------------------------------------------------------- 1. execution server
if ($ServerBinDir) {
    $serverBin = (Resolve-Path $ServerBinDir).Path
    Step "Using prebuilt execution server: $serverBin"
}
else {
    if (-not $InteropDir) { throw 'Pass -InteropDir <folder with the 3 SolidWorks.Interop.*.dll files> (or -ServerBinDir).' }
    $InteropDir = (Resolve-Path $InteropDir).Path
    foreach ($dll in 'SolidWorks.Interop.sldworks.dll', 'SolidWorks.Interop.swconst.dll', 'SolidWorks.Interop.swpublished.dll') {
        if (-not (Test-Path (Join-Path $InteropDir $dll))) { throw "Missing $dll in $InteropDir" }
    }
    $swVer = (Get-Item (Join-Path $InteropDir 'SolidWorks.Interop.sldworks.dll')).VersionInfo.FileVersion
    Step "SolidWorks interop $swVer from $InteropDir"

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found - install Visual Studio 2022 or Build Tools.' }
    $msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
    if (-not $msbuild) { throw 'MSBuild not found.' }

    $sln = Join-Path $repo 'execution\solidworks\SolidworksExecution.sln'
    Step 'Restoring NuGet packages'
    Invoke-Checked $msbuild @($sln, '/t:Restore', '/p:RestorePackagesConfig=true', '/nologo', '/v:m')
    Step 'Building execution server (Release)'
    Invoke-Checked $msbuild @($sln, '/t:Rebuild', '/p:Configuration=Release', "/p:SolidWorksApiRedist=$InteropDir", '/nologo', '/v:m')
    $serverBin = Join-Path $repo 'execution\solidworks\SolidworksExecution\bin\Release'
}
if (-not (Test-Path (Join-Path $serverBin 'SolidworksExecution.exe'))) { throw "SolidworksExecution.exe not found in $serverBin" }

# ---------------------------------------------------------------- 2. stage
Step "Staging into $stageDir"
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
New-Item -ItemType Directory -Force $appDir, $cacheDir | Out-Null

Copy-Tree $serverBin (Join-Path $appDir 'server') -excludeFiles @('*.xml', '*.vshost.*')
Copy-Tree (Join-Path $repo 'adapters\claude') (Join-Path $appDir 'adapters\claude') -excludeFiles @('*.md', 'requirements-dev.txt')
Copy-Tree (Join-Path $repo 'cad-planner') (Join-Path $appDir 'cad-planner') -excludeFiles @('architecture.md')
Copy-Tree (Join-Path $repo 'compiler\solidworks') (Join-Path $appDir 'compiler\solidworks') -excludeFiles @('*.md', '.gitkeep')
New-Item -ItemType Directory -Force (Join-Path $appDir 'tools') | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'assets\register-claude.ps1') (Join-Path $appDir 'tools')
Copy-Item (Join-Path $repo 'LICENSE'), (Join-Path $repo 'README.md') $appDir

# ---------------------------------------------------------------- 3. embedded Python
if (-not $PythonEmbedSha256.ContainsKey($PythonVersion)) { throw "No pinned SHA-256 for Python $PythonVersion - add it to `$PythonEmbedSha256." }
$zipName = "python-$PythonVersion-embed-amd64.zip"
$zip = Join-Path $cacheDir $zipName
if (-not (Test-Path $zip)) {
    Step "Downloading $zipName"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest "https://www.python.org/ftp/python/$PythonVersion/$zipName" -OutFile $zip -UseBasicParsing
}
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $PythonEmbedSha256[$PythonVersion]) { Remove-Item $zip; throw "SHA-256 mismatch for $zipName (got $hash)." }

$pyDir = Join-Path $appDir 'python'
Expand-Archive $zip $pyDir
$tag = ($PythonVersion.Split('.')[0..1]) -join ''           # 3.13.14 -> 313
$pth = Join-Path $pyDir "python$tag._pth"
# sys.path for the private runtime: stdlib, site-packages and the adapter folder (server.py's siblings).
@("python$tag.zip", '.', 'Lib\site-packages', '..\adapters\claude', 'import site') |
    Set-Content $pth -Encoding ascii

$sitePackages = Join-Path $pyDir 'Lib\site-packages'
$hostPython = $null
foreach ($cand in @(@('py', '-3'), @('python'))) {
    if (Get-Command $cand[0] -ErrorAction SilentlyContinue) { $hostPython = $cand; break }
}
if (-not $hostPython) { throw 'A Python 3 with pip is needed on the build machine to download wheels.' }
$pyMinor = ($PythonVersion.Split('.')[0..1]) -join '.'
Step "Installing adapter dependencies for Python $pyMinor (win_amd64 wheels)"
$pipArgs = @()
if ($hostPython.Length -gt 1) { $pipArgs += $hostPython[1..($hostPython.Length - 1)] }
$pipArgs += @('-m', 'pip', 'install', '--disable-pip-version-check', '--no-compile',
              '--only-binary=:all:', '--platform', 'win_amd64', '--python-version', $pyMinor,
              '--implementation', 'cp', '--target', $sitePackages,
              '-r', (Join-Path $repo 'adapters\claude\requirements.txt'))
Invoke-Checked $hostPython[0] $pipArgs

$embeddedPy = Join-Path $pyDir 'python.exe'
Step 'Pre-compiling dependencies'
Invoke-Checked $embeddedPy @('-m', 'compileall', '-q', '-j', '0', '--invalidation-mode', 'unchecked-hash', $sitePackages)

Step 'Smoke test: importing the adapter with the bundled runtime'
Push-Location (Join-Path $appDir 'adapters\claude')
try {
    Invoke-Checked $embeddedPy @('-B', (Join-Path $PSScriptRoot 'assets\smoke_test.py'))
}
finally { Pop-Location }

# ---------------------------------------------------------------- 4. license RTF for the installer UI
$lic = [IO.File]::ReadAllText((Join-Path $repo 'LICENSE'))
$lic = $lic.Replace('\', '\\').Replace('{', '\{').Replace('}', '\}')
$lic = ($lic -replace "`r?`n", "\par`r`n")
$rtf = "{\rtf1\ansi\deff0{\fonttbl{\f0 Consolas;}}\fs16`r`n$lic`r`n}"
[IO.File]::WriteAllText((Join-Path $stageDir 'license.rtf'), $rtf, [Text.Encoding]::ASCII)

# ---------------------------------------------------------------- 5. MSI
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'The .NET SDK (dotnet) is required to run WiX.' }
Step "Building MSI $Version"
Invoke-Checked 'dotnet' @('build', (Join-Path $PSScriptRoot 'SolidPilot.wixproj'), '-c', 'Release', '-nologo',
                          "-p:StageDir=$stageDir", "-p:ProductVersion=$Version", '-o', $outDir)

$msi = Join-Path $outDir "SolidPilot-$Version-x64.msi"
Step "Done: $msi"
