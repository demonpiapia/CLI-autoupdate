#Requires -Version 7.4
<#
.SYNOPSIS
    Shared helpers for the CLI update / sync scripts. Dot-source, do not run.

.DESCRIPTION
    Anti-hang guarantee: EVERY external process goes through Invoke-Proc, which
    reads stdout+stderr ASYNCHRONOUSLY before WaitForExit(timeout) and Kills the
    child on timeout. No subprocess can block forever.

    The old update scripts hung because they spawned probe-clis.ps1 via the `&`
    operator (synchronous stdout pipe, deadlocks once the child writes past the
    ~32 KB pipe buffer — probe's `mise ls-remote codex --json` is exactly that
    size). probe-clis.ps1 is archived (probe-clis-with-mistake.ps1); these
    scripts no longer call it. Each script does its own detection inline.

    Cherry Studio's mise install lives under a custom Toolchain dir, NOT the
    default %LOCALAPPDATA%\mise. Any mise subprocess MUST be given the Cherry
    MISE_* env (via Invoke-Proc -ExtraEnv) or mise looks in the wrong place and
    finds no installs. Verified 2026-09-16.

    Constants are returned by getter functions (not top-level vars) so callers
    dot-sourcing this file don't have to reason about PowerShell script-scope
    visibility of shared variables.

    Usage from a sibling script:
        . (Join-Path $PSScriptRoot 'cli-common.ps1')
#>

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# --------------------------------------------------------------------------
# Constants (getters)
# --------------------------------------------------------------------------

function Get-CherryMiseEnv {
    # Verified from Cherry Studio's injected environment, 2026-09-16.
    return [ordered]@{
        MISE_DATA_DIR     = 'E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise'
        MISE_CONFIG_DIR   = 'E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\config'
        MISE_SHIMS_DIR    = 'E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\shims'
        MISE_CACHE_DIR    = 'E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\cache'
        MISE_STATE_DIR    = 'E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\state'
        MISE_YES          = '1'
        MISE_NO_ANALYTICS = '1'
    }
}

function Get-MiseExePath   { return 'C:\Users\JasonPC\.cherrystudio\bin\mise.exe' }
function Get-MiseInstallsDir { return 'E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs' }
function Get-NpmPrefix     { return 'E:\Users\WIN_11\AppData\Roaming\npm' }

# Per-CLI source resolution metadata: how to find the active exe + its version.
function Get-CliSpec {
    param([ValidateSet('claude','codex','opencode')][string]$Name)
    switch ($Name) {
        'claude'   { return [pscustomobject]@{ Name='claude';   Channel='mise'; ExeRelPath='claude.exe';        Package=$null;                NpmPkg=$null } }
        'codex'    { return [pscustomobject]@{ Name='codex';    Channel='mise'; ExeRelPath='bin\codex.exe';      Package=$null;                NpmPkg=$null } }
        'opencode' { return [pscustomobject]@{ Name='opencode'; Channel='npm';  ExeRelPath=$null;                Package='opencode-ai';        NpmPkg='opencode-ai' } }
    }
}

# --------------------------------------------------------------------------
# Subprocess runner (deadlock-safe)
# --------------------------------------------------------------------------

function Invoke-Proc {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutMs = 300000,
        [hashtable]$ExtraEnv = $null
    )
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = ''; Error = 'empty FilePath' }
    }
    if (-not (Test-Path -LiteralPath $FilePath)) {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = ''; Error = "not found: $FilePath" }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    # Batch files (.cmd/.bat) cannot be executed directly via CreateProcess with
    # UseShellExecute=false — .NET passes args in a way npm.cmd mis-parses (npm
    # sees no subcommand, exits 1 with usage dump). Route them through cmd.exe /c.
    # Verified 2026-09-16: `cmd /c npm install -g opencode-ai@<v> --force` exits 0
    # and produces a real binary; direct npm.cmd via ProcessStartInfo exits 1.
    $realArgs = $Arguments
    if ($FilePath -match '\.(cmd|bat)$') {
        $psi.FileName = "$env:SystemRoot\System32\cmd.exe"
        $realArgs = @('/c', $FilePath) + $Arguments
    } else {
        $psi.FileName = $FilePath
    }
    foreach ($a in $realArgs) { $psi.ArgumentList.Add($a) }
    if ($ExtraEnv) {
        foreach ($k in $ExtraEnv.Keys) { $psi.EnvironmentVariables[$k] = $ExtraEnv[$k] }
    }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try { $proc.Start() | Out-Null }
    catch {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = ''; Error = "start failed: $($_.Exception.Message)" }
    }
    # Drain BOTH streams asynchronously BEFORE WaitForExit. If the child writes
    # more than the pipe buffer (~32 KB) and nobody is reading, it blocks and the
    # wait never returns. ReadToEndAsync + Task.Wait(int) is used because this
    # PowerShell build (7.6.4) cannot resolve two-arg Task.Run / StartNew.
    $tOut = $proc.StandardOutput.ReadToEndAsync()
    $tErr = $proc.StandardError.ReadToEndAsync()
    $timedOut = -not $proc.WaitForExit($TimeoutMs)
    if ($timedOut) { try { $proc.Kill() } catch { } }
    try { [void]$tOut.Wait(5000) } catch { }
    try { [void]$tErr.Wait(5000) } catch { }
    if ($timedOut) {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = ''; Error = "timeout after ${TimeoutMs}ms" }
    }
    $stdout = ''; $stderr = ''
    try { $stdout = $tOut.Result } catch { }
    try { $stderr = $tErr.Result } catch { }
    return [pscustomobject]@{ Ok = $true; ExitCode = $proc.ExitCode; Output = $stdout; Error = $stderr }
}

# --------------------------------------------------------------------------
# Filesystem / lock helpers
# --------------------------------------------------------------------------

# True if the file is held open by another process.
# MUST use FileAccess.Write: on Windows a running .exe (PE image) can always be
# opened for READ regardless of share mode, so a Read-based check cannot detect
# an in-use binary. Write+None discriminates. Handle closed immediately, no bytes written.
function Test-FileLocked {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        return $false
    }
    catch [System.IO.IOException] { return $true }
    finally { if ($fs) { $fs.Dispose() } }
}

function Get-FreeBytes {
    param([string]$Path)
    if (-not $Path) { return $null }
    try { $root = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Path).Path).TrimEnd('\') } catch { return $null }
    $d = Get-PSDrive -Name $root -PSProvider FileSystem -ErrorAction SilentlyContinue
    if (-not $d) { return $null }
    return [long]$d.Free
}

function Write-Head {
    param([string]$Title, [string]$Mode)
    Write-Output ''
    Write-Output ('=' * 72)
    Write-Output ("  {0}   [{1}]" -f $Title, $Mode)
    Write-Output ('=' * 72)
}

# --------------------------------------------------------------------------
# Semver
# --------------------------------------------------------------------------

# Returns 1 if a>b, -1 if a<b, 0 if equal. Strips leading 'v'. Only compares
# stable (core) segments; callers filter prereleases out before comparing.
function Compare-SemVer {
    param([string]$a, [string]$b)
    function parse([string]$s) {
        $s = ($s -replace '^\s*v', '').Trim()
        $core = ($s -split '-',2)[0]
        $parts = $core -split '\.' | ForEach-Object { try { [int]$_ } catch { 0 } }
        while ($parts.Count -lt 3) { $parts += 0 }
        return @([int]$parts[0], [int]$parts[1], [int]$parts[2])
    }
    $pa = parse $a; $pb = parse $b
    for ($i = 0; $i -lt 3; $i++) {
        if ($pa[$i] -ne $pb[$i]) { return [int][Math]::Sign($pa[$i] - $pb[$i]) }
    }
    return 0
}

function Test-IsStable {
    param([string]$Version)
    if (-not $Version) { return $false }
    return $Version -notmatch '-'
}

# --------------------------------------------------------------------------
# Locators
# --------------------------------------------------------------------------

function Get-NpmCmd {
    $g = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($g -and $g.Source) { return $g.Source }
    $c = Join-Path (Get-NpmPrefix) 'npm.cmd'
    if (Test-Path -LiteralPath $c) { return $c }
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $c2 = Join-Path (Split-Path $node.Source) 'npm.cmd'
        if (Test-Path -LiteralPath $c2) { return $c2 }
    }
    return $null
}

# Pure filesystem scan of the mise installs dir. No mise subprocess, no PATH,
# no MISE_* env. Returns the active exe + version for the highest semver version
# directory that actually contains the exe. Works in any shell context
# (scheduled task agent, external terminal) — this is the anti-hang, anti-PATH
# resolver.
function Resolve-MiseExeByScan {
    param([string]$Tool, [string]$ExeRelPath)
    $installs = Join-Path (Get-MiseInstallsDir) $Tool
    if (-not (Test-Path -LiteralPath $installs)) { return $null }
    $bestExe = $null; $bestVer = $null
    foreach ($d in Get-ChildItem -LiteralPath $installs -Directory -ErrorAction SilentlyContinue) {
        $exe = Join-Path $d.FullName $ExeRelPath
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        if (-not $bestVer -or (Compare-SemVer $d.Name $bestVer) -gt 0) {
            $bestExe = $exe; $bestVer = $d.Name
        }
    }
    if (-not $bestExe) { return $null }
    return [pscustomobject]@{ Exe = $bestExe; Version = $bestVer }
}

# Resolve the active installed exe for a CLI by filesystem (mise CLIs) or npm
# prefix (opencode). Returns @{ Exe; Version } where Version is read by running
# the exe --version (so it reflects the real binary, not just the dir name).
# For npm-channel CLIs, falls back to package.json when --version fails.
function Get-InstalledExe {
    param([string]$Name)
    $spec = Get-CliSpec -Name $Name
    if ($spec.Channel -eq 'mise') {
        $found = Resolve-MiseExeByScan -Tool $Name -ExeRelPath $spec.ExeRelPath
        if (-not $found) { return $null }
        $ver = Get-ExeVersion -ExePath $found.Exe
        return [pscustomobject]@{ Exe = $found.Exe; Version = $ver; DirVersion = $found.Version }
    }
    # npm channel (opencode)
    $exe = Join-Path (Get-NpmPrefix) "node_modules\$($spec.NpmPkg)\bin\opencode.exe"
    $pkgJson = Join-Path (Get-NpmPrefix) "node_modules\$($spec.NpmPkg)\package.json"
    # Version from package.json — the exe is an UNRELIABLE source: opencode-ai's
    # postinstall copies the platform binary (opencode-windows-x64 optionalDep) into
    # bin\. If that optionalDep isn't fetched, bin\opencode.exe stays as a ~479 B
    # placeholder stub ("not a valid application for this OS platform") and --version
    # fails. package.json always carries the real version. Verified 2026-09-16.
    $ver = $null
    if (Test-Path -LiteralPath $pkgJson) {
        try { $ver = (Get-Content -LiteralPath $pkgJson -Raw | ConvertFrom-Json).version } catch { }
    }
    # ExeHealthy = the exe is a real binary (> 1 MB) AND can start --version.
    # Callers use this to detect the stub and force a repair reinstall.
    $healthy = $false
    if ($exe -and (Test-Path -LiteralPath $exe)) {
        if ((Get-Item -LiteralPath $exe).Length -gt 1MB) {
            $healthy = [bool](Get-ExeVersion -ExePath $exe)
        }
    }
    return [pscustomobject]@{ Exe = $exe; Version = $ver; DirVersion = $null; ExeHealthy = $healthy }
}

# Run <exe> --version and parse the first x.y.z token. Safe (Invoke-Proc, timeout).
function Get-ExeVersion {
    param([string]$ExePath, [int]$TimeoutMs = 30000)
    $r = Invoke-Proc -FilePath $ExePath -Arguments @('--version') -TimeoutMs $TimeoutMs
    if (-not $r.Ok -or $r.ExitCode -ne 0) { return $null }
    $line = ($r.Output -split "`r?`n" | Select-Object -First 1)
    if ($line -match '(\d+\.\d+\.\d+(?:[-+0-9A-Za-z.]+)?)') { return $matches[1] }
    return $null
}

# Highest STABLE in mise's registry for $Tool. Uses mise ls-remote --json via
# the safe runner. Returns @{ Latest; Count; Error }.
function Get-MiseRemoteStableLatest {
    param([string]$Tool, [int]$TimeoutMs = 60000)
    $mise = Get-MiseExePath
    $r = Invoke-Proc -FilePath $mise -Arguments @('ls-remote', $Tool, '--json') -TimeoutMs $TimeoutMs -ExtraEnv (Get-CherryMiseEnv)
    if (-not $r.Ok) { return [pscustomobject]@{ Latest = $null; Count = $null; Error = $r.Error } }
    if ($r.ExitCode -ne 0) { return [pscustomobject]@{ Latest = $null; Count = $null; Error = "mise ls-remote exit $($r.ExitCode)" } }
    try { $rows = @($r.Output | ConvertFrom-Json) } catch { return [pscustomobject]@{ Latest = $null; Count = $null; Error = "json: $($_.Exception.Message)" } }
    $stable = @($rows | Where-Object { $_.version -and (Test-IsStable $_.version) })
    if (-not $stable.Count) { return [pscustomobject]@{ Latest = $null; Count = $rows.Count; Error = $null } }
    $hi = $stable[0].version
    foreach ($s in $stable) { if ((Compare-SemVer $s.version $hi) -gt 0) { $hi = $s.version } }
    return [pscustomobject]@{ Latest = $hi; Count = $rows.Count; Error = $null }
}

# True if $Target is present in mise's registry for $Tool (reachability check).
function Test-MiseVersionAvailable {
    param([string]$Tool, [string]$Target, [int]$TimeoutMs = 60000)
    $mise = Get-MiseExePath
    $r = Invoke-Proc -FilePath $mise -Arguments @('ls-remote', $Tool, '--json') -TimeoutMs $TimeoutMs -ExtraEnv (Get-CherryMiseEnv)
    if (-not $r.Ok) { return [pscustomobject]@{ Available = $false; Count = $null; Reason = $r.Error } }
    if ($r.ExitCode -ne 0) { return [pscustomobject]@{ Available = $false; Count = $null; Reason = "mise ls-remote exit $($r.ExitCode)" } }
    try { $rows = @($r.Output | ConvertFrom-Json) } catch { return [pscustomobject]@{ Available = $false; Count = $null; Reason = "json: $($_.Exception.Message)" } }
    $hit = @($rows | Where-Object { $_.version -eq $Target })
    if (-not $hit.Count) { return [pscustomobject]@{ Available = $false; Count = $rows.Count; Reason = "not in mise registry ($($rows.Count) entries)" } }
    return [pscustomobject]@{ Available = $true; Count = $rows.Count; Reason = $null }
}

# npm registry latest version string for $Pkg.
function Get-NpmRegistryLatest {
    param([string]$Pkg, [int]$TimeoutMs = 60000)
    $npm = Get-NpmCmd
    if (-not $npm) { return $null }
    $r = Invoke-Proc -FilePath $npm -Arguments @('view', $Pkg, 'version') -TimeoutMs $TimeoutMs
    if (-not $r.Ok -or $r.ExitCode -ne 0) { return $null }
    $v = ($r.Output -split "`r?`n" | Select-Object -First 1).Trim()
    if ($v -match '^\d+\.\d+\.\d+') { return $v }
    return $null
}
