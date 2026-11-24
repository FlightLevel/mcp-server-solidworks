<#
.SYNOPSIS
  Adds (or removes) the SolidPilot MCP server in Claude Desktop's claude_desktop_config.json.

.DESCRIPTION
  Installed to <install>\tools\ by the SolidPilot MSI and run by it at install/uninstall time.
  Updates every Claude Desktop config it finds (regular install under %APPDATA%\Claude and the
  Microsoft Store/MSIX install under %LOCALAPPDATA%\Packages\Claude_*). If none exists yet, it
  creates %APPDATA%\Claude\claude_desktop_config.json. A .bak copy is written before any change.
  Restart Claude Desktop afterwards.
#>
param(
    [switch]$Unregister,
    [string]$ServerName = 'SolidPilot',
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'
$installDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$python = Join-Path $installDir 'python\python.exe'
$adapterDir = Join-Path $installDir 'adapters\claude'
$serverPy = Join-Path $adapterDir 'server.py'

function Get-ConfigPaths {
    $paths = @()
    $roaming = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
    if (Test-Path $roaming) { $paths += $roaming }
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $pkgRoot) {
        foreach ($pkg in Get-ChildItem $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue) {
            $p = Join-Path $pkg.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json'
            if (Test-Path $p) { $paths += $p }
        }
    }
    if ($paths.Count -eq 0 -and -not $Unregister) { $paths += $roaming }
    return $paths
}

function Write-Utf8NoBom([string]$path, [string]$text) {
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

$exit = 0
foreach ($cfgPath in Get-ConfigPaths) {
    try {
        $cfg = $null
        if (Test-Path $cfgPath) {
            $raw = [IO.File]::ReadAllText($cfgPath)
            if ($raw.Trim()) { $cfg = $raw | ConvertFrom-Json }
        }
        if ($null -eq $cfg) { $cfg = New-Object PSObject }

        if ($Unregister) {
            if (-not $cfg.mcpServers -or -not ($cfg.mcpServers.PSObject.Properties.Name -contains $ServerName)) {
                Write-Host "Not registered: $cfgPath"
                continue
            }
            # Only remove an entry that points at THIS install.
            $existing = $cfg.mcpServers.$ServerName
            if ($existing.command -and -not ([string]$existing.command).StartsWith($installDir, [StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "Leaving '$ServerName' in $cfgPath (it points somewhere else: $($existing.command))"
                continue
            }
            Copy-Item $cfgPath "$cfgPath.bak" -Force
            $cfg.mcpServers.PSObject.Properties.Remove($ServerName)
            Write-Utf8NoBom $cfgPath ($cfg | ConvertTo-Json -Depth 100)
            Write-Host "Removed '$ServerName' from $cfgPath"
        }
        else {
            if (-not $cfg.mcpServers) {
                $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue (New-Object PSObject) -Force
            }
            $entry = [ordered]@{
                command = $python
                args    = @('-B', $serverPy)
                cwd     = $adapterDir
            }
            $cfg.mcpServers | Add-Member -NotePropertyName $ServerName -NotePropertyValue ([pscustomobject]$entry) -Force
            if (Test-Path $cfgPath) { Copy-Item $cfgPath "$cfgPath.bak" -Force }
            Write-Utf8NoBom $cfgPath ($cfg | ConvertTo-Json -Depth 100)
            Write-Host "Registered '$ServerName' in $cfgPath"
        }
    }
    catch {
        Write-Warning "Could not update ${cfgPath}: $($_.Exception.Message)"
        $exit = 1
    }
}

Write-Host 'Restart Claude Desktop to pick up the change.'
if ($Pause) { Read-Host 'Press Enter to close' | Out-Null }
exit $exit
