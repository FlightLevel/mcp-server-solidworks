# SolidPilot Windows installer

`build.ps1` produces `installer\out\SolidPilot-<version>-x64.msi`, a self-contained installer: the
C# execution server, the Python MCP adapter (with `cad-planner` and the IR compiler) and a private
embedded Python runtime with every dependency pre-installed. End users need only SolidWorks
(2024 or newer) and Claude Desktop. They don't need Python, .NET SDK or admin rights.

## Build machine

SolidWorks is **not** required. You need:

- Visual Studio 2022 or Build Tools 2022 with the **.NET desktop development** workload (MSBuild and
  the .NET Framework 4.8 targeting pack).
- The **.NET SDK** 6 or newer (`dotnet`). WiX Toolset 5 is restored from NuGet automatically.
- **Python 3** with pip (only used to download the Windows wheels).
- Internet access (NuGet, PyPI, python.org).
- The three SolidWorks interop DLLs, copied from `<SolidWorks 2024 install>\api\redist\` on any
  SolidWorks machine into one folder:
  - `SolidWorks.Interop.sldworks.dll`
  - `SolidWorks.Interop.swconst.dll`
  - `SolidWorks.Interop.swpublished.dll`

  Build against **2024** interop. The result runs on SolidWorks 2024, 2025 and 2026.

## Build

```powershell
.\installer\build.ps1 -InteropDir C:\sw2024-interop -Version 1.0.0
```

| Parameter | Meaning |
|---|---|
| `-InteropDir` | Folder with the three interop DLLs. |
| `-Version` | MSI version `major.minor.build`. Raise it for every release so upgrades replace the old install. |
| `-ServerBinDir` | Package an already-built execution server folder instead of building it (no interop needed). |
| `-PythonVersion` | Embedded Python to bundle (default `3.13.14`; the zip's SHA-256 is pinned in the script). |

The script builds the server (Release), stages everything under `installer\out\stage`, runs a smoke
test that imports the whole adapter with the bundled Python, then runs WiX. Downloads are cached in
`installer\cache`.

## What the MSI does

- Installs per user to `%LOCALAPPDATA%\Programs\SolidPilot` (no UAC prompt):
  `server\` (execution server), `adapters\claude\` (MCP adapter), `cad-planner\`, `compiler\`,
  `python\` (embedded runtime), `tools\register-claude.ps1`.
- Registers a `SolidPilot` entry in Claude Desktop's `claude_desktop_config.json` (regular and
  Microsoft Store installs; a `.bak` copy is kept). Skip with `msiexec /i SolidPilot-1.0.0-x64.msi REGISTER_CLAUDE=0`.
- Adds Start Menu shortcuts: register / unregister with Claude Desktop, open the install folder.
- Upgrading: installing a higher `-Version` replaces the previous one.
- Uninstall (Settings → Apps) removes the files, logs, shortcuts and the Claude Desktop entry.

The adapter starts the execution server by itself on the first tool call. Users restart Claude
Desktop after installing.

## Distribution notes

- The MSI is **unsigned**, so Windows SmartScreen will warn on download. To avoid that, sign it with a
  code-signing certificate:
  `signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a installer\out\SolidPilot-1.0.0-x64.msi`
- The SolidWorks interop DLL `SolidWorks.Interop.sldworks.dll` is shipped inside the MSI (it is from
  SolidWorks' `redist` folder).
- WiX Toolset is open source; check its current Open Source Maintenance Fee terms if you build
  installers commercially.
- The project is under the license in `LICENSE`. It is shown in the installer and installed alongside the app.
