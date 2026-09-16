#requires -Version 7.4
<#
.SYNOPSIS
    Batch-probe version / install-channel info for the local AI coding CLIs.

.DESCRIPTION
    Covers claude code, codex and opencode. For each CLI this script reports:

      * selectedCommand  - the command that wins PATH resolution
      * resolvedVia      - path | mise-which | mise-ls+scan | install-scan | none
      * channel          - npm global / mise / other / none   (the ACTIVE install channel)
      * version          - parsed version, plus the raw --version string
      * package          - npm package name + declared version (from package.json)
      * nativeExe        - resolved native binary path + byte size
      * installTime      - package / install dir last-modified timestamp
      * installBytes     - real size, hardlinks counted once
      * channelLatest    - latest version ON THE ACTIVE CHANNEL (what matters)
      * isLatest / behindPatch / channelVerdict  - judged against channelLatest
      * actionable       - true = an update is available on the active channel
      * otherChannel / otherChannelLatest / crossChannelNewer
                          - a DIFFERENT channel has something newer. Informational
                          only: the active channel cannot reach it, so it must not
                          drive an auto-update.
      * registryLatest   - npm registry latest (informational, all CLIs)
      * shadowed         - distinct duplicate installs that lost the PATH race
      * otherInstalls    - installs discovered that are NOT on PATH
      * configHits       - resolved config/state locations + sizes
      * updateCommand    - the update entry point for this channel

    VERSION COMPARISON IS CHANNEL-SCOPED. This is the whole point: codex is
    installed via mise, so `@openai/codex` on the npm registry (0.154.0) is NOT a
    reachable target for it - `mise upgrade codex` cannot get there. Verified
    against `mise ls-remote codex --json`: 360 entries, 151 stable, highest
    stable 0.152.0, then only 0.153.0-alpha.1/.2, and no 0.154.0 at all. Judging
    the installed 0.152.0 against npm 0.154.0 would report a false "behind" that
    no available update command can satisfy. So:

        channelLatest   = mise ls-remote highest stable   (mise channel)
                        = npm registry latest             (npm channel)
        crossChannelNewer is reported separately and never sets actionable.

    Add -IncludePrerelease to let codex track mise's alpha channel
    (0.153.0-alpha.2 as of 2026-09-15); mise's "latest" selector is stable-only.

    Resolution is deliberately NOT dependent on PATH: PATH is tried first, then
    `mise which`, then `mise ls` + install-dir scan, then a pure directory scan,
    then the npm prefix. This matters because mise shim executables only work
    when the MISE_* environment is present; outside a host that injects it, the
    shim may be on PATH yet unusable, or the shim dir may be absent from PATH
    entirely. The authoritative installed binary is used in both cases.

    This script is READ-ONLY: it never installs, uninstalls or upgrades anything.
    Diagnostic field labels are English by convention; use -Json for machine output.

.PARAMETER Cli
    Subset of CLIs to probe. Default: all three.

.PARAMETER SkipRemote
    Skip all network lookups (npm registry AND mise ls-remote). Offline probe.

.PARAMETER SkipRegistry
    Alias of -SkipRemote. Kept for backwards compatibility.

.PARAMETER IncludePrerelease
    For mise-channel CLIs, count prerelease versions (alpha/beta/rc/dev/nightly/
    canary) as reachable. Off by default, matching mise's "latest" selector.

.PARAMETER Json
    Emit a single JSON document instead of the human-readable report.

.PARAMETER RegistryTimeoutSec
    Per-lookup timeout in seconds (npm view and mise ls-remote). Default 20.

.PARAMETER ExitIfBehind
    Exit 3 when any probed CLI is actionable (update available on its channel).
    Useful for scheduled jobs: 0 = nothing to do, 2 = probe failed, 3 = update.

.OUTPUTS
    Human-readable report by default, or one JSON document with -Json.

.EXAMPLE
    pwsh -NoProfile -File .\probe-clis.ps1

.EXAMPLE
    pwsh -NoProfile -File .\probe-clis.ps1 -Json -SkipRemote

.EXAMPLE
    pwsh -NoProfile -File .\probe-clis.ps1 -Cli codex -IncludePrerelease

.EXAMPLE
    pwsh -NoProfile -File .\probe-clis.ps1 -Json -ExitIfBehind
#>
param(
    [string[]]$Cli = @('claude', 'codex', 'opencode'),
    [switch]$SkipRemote,
    [switch]$SkipRegistry,
    [switch]$IncludePrerelease,
    [switch]$Json,
    [int]$RegistryTimeoutSec = 20,
    [switch]$ExitIfBehind
)

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$ErrorActionPreference = 'Continue'
$SkipRemote = $SkipRemote -or $SkipRegistry

# ===========================================================================
# Helpers
# ===========================================================================

# Run an executable with a real timeout; never throws.
function Run-Exe {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutMs = 30000
    )

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = ''; Error = 'empty FilePath' }
    }
    if (-not (Test-Path -LiteralPath $FilePath)) {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = ''; Error = "not found: $FilePath" }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        $proc.Start() | Out-Null
    } catch {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = ''; Error = "start failed: $($_.Exception.Message)" }
    }

    # Drain both streams concurrently with the async readers BEFORE waiting.
    # Reading them only after WaitForExit deadlocks: a child that writes more
    # than the pipe buffer blocks on the full pipe, so WaitForExit never
    # returns and every call looks like a timeout. Measured case:
    # `mise ls-remote codex --json` (32183 B) stalled past 120 s with the old
    # ordering and takes 130 ms with this one.
    #
    # ReadToEndAsync() is used rather than Task.Run()/Task.Factory.StartNew():
    # this PowerShell build cannot resolve either 2-argument overload
    # ("Cannot find an overload ... argument count: 2"), so delegate conversion
    # is not an option here.
    $tOut = $proc.StandardOutput.ReadToEndAsync()
    $tErr = $proc.StandardError.ReadToEndAsync()

    $timedOut = -not $proc.WaitForExit($TimeoutMs)
    if ($timedOut) {
        try { $proc.Kill() } catch { }
    }
    try { [void]$tOut.Wait(5000) } catch { }
    try { [void]$tErr.Wait(5000) } catch { }
    if ($timedOut) {
        return [pscustomobject]@{ Ok = $false; ExitCode = $null; Output = ''; Error = "timeout after ${TimeoutMs}ms" }
    }

    $stdout = ''
    $stderr = ''
    try { $stdout = $tOut.Result } catch { }
    try { $stderr = $tErr.Result } catch { }
    $lines = @($stdout -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    return [pscustomobject]@{
        Ok       = $true
        ExitCode = $proc.ExitCode
        Output   = $lines -join "`n"
        Error    = $stderr.Trim()
    }
}

function Get-Version {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $m = [regex]::Match($Raw, '(\d+(?:\.\d+)+(?:[-+][0-9A-Za-z.-]+)?)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $Raw.Trim()
}

# Semver-style precedence for two version strings.
#   +1  : $Newer is newer than $Older
#   -1  : $Older is newer
#    0  : equal
# A release beats every prerelease of the same numeric core, and prerelease
# identifiers compare per-semver: numerics compare numerically and a numeric
# identifier outranks a non-numeric one. Without this, an equal core with an
# unscored tiebreak picked whichever entry appeared first in the list, which
# made '0.153.0-alpha.1' win over '0.153.0-alpha.2'.
function Test-VersionNewer {
    param([string]$Older, [string]$Newer)

    $a = [regex]::Match($Older, '^(\d+)\.(\d+)\.(\d+)(.*)$')
    $b = [regex]::Match($Newer, '^(\d+)\.(\d+)\.(\d+)(.*)$')
    if (-not $a.Success) { return 1 }
    if (-not $b.Success) { return -1 }

    foreach ($i in 1..3) {
        $x = [int]$a.Groups[$i].Value
        $y = [int]$b.Groups[$i].Value
        if ($x -ne $y) { $r = if ($y -gt $x) { 1 } else { -1 }; return $r }
    }

    $sa = $a.Groups[4].Value
    $sb = $b.Groups[4].Value
    # Build metadata ('+...') carries no precedence weight - strip it.
    $sa = ($sa -split '\+', 2)[0]
    $sb = ($sb -split '\+', 2)[0]
    if ($sa -eq $sb) { return 0 }
    if ($sa -eq '') { return -1 }   # $Older is the release
    if ($sb -eq '') { return 1 }    # $Newer is the release
    $ia = @($sa -split '\.')
    $ib = @($sb -split '\.')
    $n = [Math]::Max($ia.Count, $ib.Count)
    for ($j = 0; $j -lt $n; $j++) {
        $pa = if ($j -lt $ia.Count) { $ia[$j] } else { '' }
        $pb = if ($j -lt $ib.Count) { $ib[$j] } else { '' }
        if ($pa -eq $pb) { continue }
        $an = [int]::MinValue; $bn = [int]::MinValue
        $aNum = [int]::TryParse($pa, [ref]$an)
        $bNum = [int]::TryParse($pb, [ref]$bn)
        if ($aNum -and $bNum) { $r = if ($bn -gt $an) { 1 } else { -1 }; return $r }
        if ($aNum -ne $bNum)  { $r = if ($bNum) { 1 } else { -1 }; return $r }
        $r = if ($pb -gt $pa) { 1 } else { -1 }; return $r
    }
    return 0
}

# Highest of a list of version strings, numeric-aware.
# String sort is wrong here ("0.10.0" < "0.9.0"), and this mise build has no
# `ls-remote --sort` flag, so the pick is done in-script.
function Get-TopVersion {
    param([string[]]$Versions)
    $best = $null
    foreach ($v in $Versions) {
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        if (-not $best) { $best = $v; continue }
        if ((Test-VersionNewer $best $v) -gt 0) { $best = $v }
    }
    return $best
}

# Real byte size of a directory, counting hardlinked files once.
#
# Hardlink detection: this PowerShell build (7.6.4) does NOT expose
# FileInfo.FileId / FileInfo.LinkCount / HardLinkCount - all three come back
# null - so there is no inode key available. Instead files are keyed by
# (byte size, last-write time), which is exactly what GNU `du -sb` uses to
# collapse same-inode files; verified byte-for-byte against `du -sb` for all
# three packages. Two genuinely distinct files with identical size AND identical
# mtime would be collapsed (under-counts), so both the deduped total and the
# naive sum are returned for auditing.
function Get-DirBytes {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $seen   = New-Object System.Collections.Generic.HashSet[string]
    $dedupe = [long]0
    $naive  = [long]0

    foreach ($f in (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)) {
        $naive  += $f.Length
        $key    = '{0}|{1}' -f $f.Length, $f.LastWriteTimeUtc.Ticks
        if ($seen.Add($key)) { $dedupe += $f.Length }
    }
    return [pscustomobject]@{ Dedupe = $dedupe; Naive = $naive }
}

# Classify a command source path into its install root.
function Get-RootKind {
    param([string]$Src)
    if ([string]::IsNullOrWhiteSpace($Src)) { return 'other' }
    if ($Src -match '[/\\]mise[/\\]shims[/\\]') { return 'mise' }
    if ($Src -match '[/\\]AppData[/\\]Roaming[/\\]npm[/\\]') { return 'npm' }
    return 'other'
}

# Normalise an npm shim path down to the command base so that
# claude / claude.cmd / claude.ps1 collapse to a single identity.
function Get-CmdBase {
    param([string]$Src)
    if ([string]::IsNullOrWhiteSpace($Src)) { return $null }
    foreach ($ext in @('.cmd', '.ps1', '.bat', '.exe')) {
        if ($Src.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
            return $Src.Substring(0, $Src.Length - $ext.Length)
        }
    }
    return $Src
}

function Get-NpmCmd {
    $g = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $c = Join-Path (Split-Path $node.Source) 'npm.cmd'
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

# Strip a leading "./", "/" or "\" from a package.json bin target.
function Get-RelPath {
    param([string]$Rel)
    if ([string]::IsNullOrWhiteSpace($Rel)) { return $Rel }
    if ($Rel.StartsWith('./')) { return $Rel.Substring(2) }
    if ($Rel.StartsWith('/') -or $Rel.StartsWith('\')) { return $Rel.Substring(1) }
    return $Rel
}

# mise data roots, in probe order. Environment first, then conventional and the
# Cherry Studio bundled toolchain layout on this machine.
function Get-MiseRoots {
    $cands = @(
        $env:MISE_DATA_DIR,
        (Join-Path $env:USERPROFILE '.local\share\mise'),
        (Join-Path $env:LOCALAPPDATA 'mise'),
        (Join-Path $env:APPDATA 'mise'),
        (Join-Path $env:APPDATA 'CherryStudio\Toolchain\mise')
    )
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c) -and $seen.Add($c)) { $roots.Add($c) }
    }
    return $roots
}

# Locate the mise binary, preferring PATH then known locations.
function Get-MiseExe {
    $g = Get-Command mise -ErrorAction SilentlyContinue
    if ($g) { return [pscustomobject]@{ Exe = $g.Source; How = 'path' } }

    $cands = @(
        (Join-Path $env:USERPROFILE '.cherrystudio\bin\mise.exe'),
        (Join-Path $env:USERPROFILE '.local\bin\mise.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\mise\bin\mise.exe')
    )
    foreach ($c in $cands) {
        if (Test-Path -LiteralPath $c) { return [pscustomobject]@{ Exe = $c; How = 'candidate' } }
    }

    foreach ($r in (Get-MiseRoots)) {
        foreach ($sub in @('.\bin\mise.exe', '.\bin\mise', '.\mise.exe')) {
            $c = Join-Path $r $sub
            if (Test-Path -LiteralPath $c) { return [pscustomobject]@{ Exe = $c; How = 'inside-root' } }
        }
    }
    return $null
}

# Authoritative mise-installed binary for a tool, independent of PATH and shims.
#
# Preferred: `mise which <tool>` (resolves the active version from mise config).
# Fallback:  `mise ls <tool> --json` for the version, then scan installs.
# Last:      scan <root>\installs\<tool>\ for the highest semver.
function Get-MiseInstall {
    param([string]$Tool, [pscustomobject]$MiseInfo)

    if ($MiseInfo) {
        $w = Run-Exe -FilePath $MiseInfo.Exe -Arguments @('which', $Tool) -TimeoutMs 20000
        if ($w.Ok -and $w.ExitCode -eq 0 -and $w.Output -and (Test-Path -LiteralPath $w.Output.Trim())) {
            return [pscustomobject]@{ Path = $w.Output.Trim(); Version = $null; How = 'mise-which' }
        }
    }

    foreach ($r in (Get-MiseRoots)) {
        $verDir = Join-Path $r ('installs\' + $Tool)
        if (-not (Test-Path -LiteralPath $verDir)) { continue }

        $dirs = @(Get-ChildItem -LiteralPath $verDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending)
        if ($dirs.Count -eq 0) { continue }

        $target = $null
        if ($MiseInfo) {
            $l = Run-Exe -FilePath $MiseInfo.Exe -Arguments @('ls', $Tool, '--json') -TimeoutMs 20000
            if ($l.Ok -and $l.ExitCode -eq 0 -and $l.Output) {
                try {
                    $row = @($l.Output | ConvertFrom-Json)[0]
                    if ($row -and $row.version) {
                        $match = $dirs | Where-Object { $_.Name -eq $row.version } | Select-Object -First 1
                        if ($match) { $target = $match.Name }
                    }
                } catch { }
            }
        }
        if (-not $target) { $target = $dirs[0].Name }

        $bin = Join-Path $verDir ($target + '\bin\' + $Tool + '.exe')
        if (Test-Path -LiteralPath $bin) {
            $how = 'install-scan'
            if ($MiseInfo) { $how = 'mise-ls+scan' }
            return [pscustomobject]@{ Path = $bin; Version = $target; How = $how }
        }
    }
    return $null
}

# Latest version reachable on the mise channel: `mise ls-remote <tool> --json`,
# highest stable by default. This is the ONLY meaningful "latest" for a
# mise-managed CLI.
#
# Returns { Value, Error, Count }. Note the mise registry is a curated
# versions-host source and LAGS the upstream repo: for codex as of 2026-09-15
# the registry's highest stable is 0.152.0 while `git ls-remote --tags` on
# github.com/openai/codex shows 0.153.1 .. 0.154.0 already published (0.154.0
# has zero entries here). The registry ceiling is what `mise upgrade` can reach,
# so that is what the verdict must be judged against - but the gap is worth
# surfacing, which is what CrossChannelNewer is for.
function Get-MiseRemoteLatest {
    param([string]$Tool, [pscustomobject]$MiseInfo, [switch]$IncludePrerelease)

    if (-not $MiseInfo) { return [pscustomobject]@{ Value = $null; Error = 'mise binary not found'; Count = $null } }

    $r = Run-Exe -FilePath $MiseInfo.Exe -Arguments @('ls-remote', $Tool, '--json') -TimeoutMs 60000
    if (-not $r.Ok) { return [pscustomobject]@{ Value = $null; Error = $r.Error; Count = $null } }
    if ($r.ExitCode -ne 0) {
        return [pscustomobject]@{ Value = $null; Error = "exit $($r.ExitCode): $($r.Error) $($r.Output)"; Count = $null }
    }
    if (-not $r.Output) { return [pscustomobject]@{ Value = $null; Error = 'empty output'; Count = $null } }

    try { $rows = @($r.Output | ConvertFrom-Json) } catch {
        return [pscustomobject]@{ Value = $null; Error = "json parse: $($_.Exception.Message)"; Count = $null }
    }
    $vs = @($rows | ForEach-Object { $_.version } | Where-Object { $_ })
    if (-not $IncludePrerelease) {
        $vs = @($vs | Where-Object { $_ -notmatch '(alpha|beta|rc|dev|nightly|canary)' })
    }
    $top = Get-TopVersion $vs
    if (-not $top) {
        return [pscustomobject]@{ Value = $null; Error = "no version parsed ($($rows.Count) entries)"; Count = $rows.Count }
    }
    return [pscustomobject]@{ Value = $top; Error = $null; Count = $rows.Count }
}

# ===========================================================================
# Environment
# ===========================================================================
$pathEntries = @($env:PATH -split ';')
$npmCmdExe = Get-NpmCmd
$npmPrefix = $null
if ($npmCmdExe) {
    $pr = Run-Exe -FilePath $npmCmdExe -Arguments @('config', 'get', 'prefix') -TimeoutMs 20000
    if ($pr.Ok -and $pr.ExitCode -eq 0 -and $pr.Output) { $npmPrefix = $pr.Output.Trim() }
}
if (-not $npmPrefix) { $npmPrefix = (Join-Path $env:APPDATA 'npm') }

$nodeExe = $null
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) { $nodeExe = $nodeCmd.Source }

$miseInfo = Get-MiseExe
$miseExe  = if ($miseInfo) { $miseInfo.Exe } else { $null }

$envInfo = [pscustomobject]@{
    GeneratedAt      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    OS               = $PSVersionTable.OS
    PowerShell       = $PSVersionTable.PSVersion.ToString()
    NodeExe          = $nodeExe
    NodeVersion      = if ($nodeExe) { (Run-Exe -FilePath $nodeExe -Arguments @('--version') -TimeoutMs 10000).Output } else { $null }
    NpmCmdExe        = $npmCmdExe
    NpmPrefix        = $npmPrefix
    MiseExe          = $miseExe
    MiseExeHow       = if ($miseInfo) { $miseInfo.How } else { $null }
    MiseDataDir      = $env:MISE_DATA_DIR
    MiseShimsDir     = $env:MISE_SHIMS_DIR
    MiseConfigDir    = $env:MISE_CONFIG_DIR
    MiseConfigFile   = $env:MISE_CONFIG_FILE
    MiseRoots        = @((Get-MiseRoots))
    PathEntryCount   = $pathEntries.Count
    PathHasMiseShims = [bool](@($pathEntries | Where-Object { $_ -match 'mise[/\\]shims' }))
    PathHasNpm       = [bool](@($pathEntries | Where-Object { $_ -match '[/\\]AppData[/\\]Roaming[/\\]npm($|[/\\])' }))
    UserHome         = $env:USERPROFILE
    AppData          = $env:APPDATA
    LocalAppData     = $env:LOCALAPPDATA
    CodeXHome        = $env:CODEX_HOME
    ClaudeConfigDir  = $env:CLAUDE_CONFIG_DIR
    RemoteSkipped    = [bool]$SkipRemote
    PrereleaseCounted = [bool]$IncludePrerelease
}

# ===========================================================================
# CLI spec table
# ===========================================================================
$Spec = @(
    [ordered]@{
        Name      = 'claude'
        Package   = '@anthropic-ai/claude-code'
        MiseTool  = $null
        UpdateCmd = 'claude update   (or: npm i -g @anthropic-ai/claude-code@latest)'
    }
    [ordered]@{
        Name      = 'codex'
        Package   = '@openai/codex'
        MiseTool  = 'codex'
        UpdateCmd = 'mise upgrade codex   (codex update only works on npm-channel installs)'
    }
    [ordered]@{
        Name      = 'opencode'
        Package   = 'opencode-ai'
        MiseTool  = $null
        UpdateCmd = 'opencode upgrade   (-m curl|npm|pnpm|bun|brew|choco|scoop)'
    }
)

# ===========================================================================
# Probe one CLI
# ===========================================================================
function Probe-Clr {
    param([System.Collections.Specialized.OrderedDictionary]$S)

    $name    = $S.Name
    $pkgName = $S.Package

    # --- 1. PATH resolution (preferred, but not required) -------------------
    $cmds = @(Get-Command -Name $name -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -in @('Application', 'Script', 'ExternalScript') })

    $selected = $null
    if ($cmds.Count -gt 0) { $selected = $cmds[0] }

    # --- 2. mise authoritative install (PATH-independent) -------------------
    $miseInstall     = $null
    $miseVersion     = $null
    $miseRequested   = $null
    $miseResolvedHow = $null
    if ($S.MiseTool) {
        $mi = Get-MiseInstall -Tool $S.MiseTool -MiseInfo $miseInfo
        if ($mi) {
            $miseInstall     = $mi.Path
            $miseResolvedHow = $mi.How
            $miseVersion     = $mi.Version
        }
        if ($miseInfo) {
            $l = Run-Exe -FilePath $miseInfo.Exe -Arguments @('ls', $S.MiseTool, '--json') -TimeoutMs 20000
            if ($l.Ok -and $l.ExitCode -eq 0 -and $l.Output) {
                try {
                    $row = @($l.Output | ConvertFrom-Json)[0]
                    if ($row) {
                        if ($row.version) { $miseVersion = $row.version }
                        $miseRequested = $row.requested_version
                    }
                } catch { }
            }
        }
    }

    # --- 3. channel ---------------------------------------------------------
    $resolvedVia = 'none'
    $channel     = 'none'
    if ($cmds.Count -gt 0) {
        $channel     = Get-RootKind $cmds[0].Source
        $resolvedVia = 'path'
    } elseif ($miseInstall) {
        $channel     = 'mise'
        $resolvedVia = $miseResolvedHow
    }

    # --- 4. off-PATH installs ----------------------------------------------
    $otherInstalls = @()
    if ($cmds.Count -eq 0) {
        if ($miseInstall) {
            $otherInstalls += [pscustomobject]@{ Channel = 'mise'; Path = $miseInstall; How = $miseResolvedHow }
        }
        if ($npmPrefix) {
            foreach ($ext in @('.exe', '.cmd', '.ps1')) {
                $c = Join-Path $npmPrefix ($name + $ext)
                if (Test-Path -LiteralPath $c) {
                    $otherInstalls += [pscustomobject]@{ Channel = 'npm'; Path = $c; How = 'npm-prefix' }
                }
            }
        }
    }

    # --- 5. shadowed duplicates (PATH hits that lost the race) -------------
    $selectedBase = if ($selected) { Get-CmdBase $selected.Source } else { $null }
    $shadowed = @()
    foreach ($base in @($cmds | ForEach-Object { Get-CmdBase $_.Source } | Where-Object { $_ }) | Sort-Object -Unique) {
        if ($base -ne $selectedBase) {
            $example = ($cmds | Where-Object { (Get-CmdBase $_.Source) -eq $base } | Select-Object -First 1).Source
            $shadowed += [pscustomobject]@{ Base = $base; Channel = (Get-RootKind $example); Example = $example }
        }
    }

    # --- 6. npm package metadata --------------------------------------------
    $pkgDir      = $null
    $pkgJson     = $null
    $nativeExe   = $null
    $nativeBytes = $null
    $nd = Join-Path $npmPrefix ('node_modules\' + ($pkgName -replace '/', '\'))
    if (Test-Path -LiteralPath $nd) {
        $pkgDir = $nd
        $pkgJsonPath = Join-Path $pkgDir 'package.json'
        if (Test-Path -LiteralPath $pkgJsonPath) {
            try { $pkgJson = Get-Content -LiteralPath $pkgJsonPath -Raw | ConvertFrom-Json } catch { $pkgJson = $null }
        }
        if ($pkgJson -and $pkgJson.bin) {
            $binRel = Get-RelPath ([string]$pkgJson.bin.$name)
            if ($binRel) {
                $binAbs = Join-Path $pkgDir ($binRel -replace '/', '\')
                if (Test-Path -LiteralPath $binAbs) {
                    $nativeExe   = $binAbs
                    $nativeBytes = (Get-Item -LiteralPath $binAbs).Length
                }
            }
        }
    }

    # --- 7. pick an executable that actually runs --------------------------
    # Priority: authoritative mise install > npm native exe > PATH shim.
    # The shim is last because it only works when the host injected MISE_*.
    $candidates = @()
    if ($miseInstall) { $candidates += $miseInstall }
    if ($nativeExe)   { $candidates += $nativeExe }
    if ($selected -and $selected.Source) { $candidates += $selected.Source }

    $exeToRun   = $null
    $rawVersion = ''
    $version    = $null
    $versionError = $null
    foreach ($c in $candidates) {
        $res = $null
        if ($c -match '\.(js|mjs|cjs)$') {
            if ($nodeExe) { $res = Run-Exe -FilePath $nodeExe -Arguments @($c, '--version') -TimeoutMs 30000 }
        } else {
            $res = Run-Exe -FilePath $c -Arguments @('--version') -TimeoutMs 30000
        }
        if ($res -and $res.Ok -and $res.ExitCode -eq 0 -and $res.Output) {
            $exeToRun   = $c
            $rawVersion = $res.Output
            $version    = Get-Version $rawVersion
            break
        }
        if (-not $versionError -and $res -and ($res.Error -or -not $res.Ok)) {
            $versionError = ('{0} :: {1} {2}' -f (Split-Path $c -Leaf), $res.Error, $res.Output)
        }
    }
    if (-not $exeToRun) {
        $versionError = if ($versionError) { $versionError } else { 'no executable resolved' }
    }

    # --- 8. install time + real size ----------------------------------------
    $installTime       = $null
    $installBytes      = $null
    $installBytesNaive = $null
    if ($pkgDir -and (Test-Path -LiteralPath $pkgDir)) {
        $installTime = (Get-Item -LiteralPath $pkgDir).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        $sz          = Get-DirBytes $pkgDir
        $installBytes      = $sz.Dedupe
        $installBytesNaive = $sz.Naive
    } elseif ($miseInstall) {
        # <root>\installs\<tool>\<version>\bin\<tool>.exe -> root is 3 levels up from bin
        $p    = Split-Path $miseInstall -Parent
        $p    = Split-Path $p -Parent
        $root = Split-Path $p -Parent
        if (Test-Path -LiteralPath $root) {
            $installTime = (Get-Item -LiteralPath $root).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            $sz          = Get-DirBytes $root
            $installBytes      = $sz.Dedupe
            $installBytesNaive = $sz.Naive
        }
    }

    # --- 9. remote latest: both channels ------------------------------------
    $registryLatest = $null
    $registryError  = $null
    if (-not $SkipRemote -and $npmCmdExe) {
        $r = Run-Exe -FilePath $npmCmdExe -Arguments @(
            'view', $pkgName, 'version',
            "--fetch-timeout=$($RegistryTimeoutSec * 1000)",
            '--fetch-retries=0'
        ) -TimeoutMs ($RegistryTimeoutSec * 1000 + 15000)
        if ($r.Ok -and $r.ExitCode -eq 0 -and $r.Output) { $registryLatest = $r.Output.Trim() }
        else { $registryError = ($r.Error + ' ' + $r.Output).Trim() }
    }

    $miseRemoteLatest = $null
    $miseRemoteError  = $null
    $miseRemoteCount  = $null
    if ($S.MiseTool -and -not $SkipRemote) {
        $ml               = Get-MiseRemoteLatest -Tool $S.MiseTool -MiseInfo $miseInfo -IncludePrerelease:$IncludePrerelease
        $miseRemoteLatest = $ml.Value
        $miseRemoteError  = $ml.Error
        $miseRemoteCount  = $ml.Count
    }

    # --- 10. channel-scoped verdict ----------------------------------------
    $channelLatest       = $null
    $channelLatestSource = $null
    $otherChannel        = $null
    $otherChannelLatest  = $null

    if ($channel -eq 'mise') {
        $channelLatest       = $miseRemoteLatest
        $channelLatestSource = if ($IncludePrerelease) { 'mise ls-remote (incl. prerelease)' }
                               else                     { 'mise ls-remote (stable only)' }
        $otherChannel        = 'npm'
        $otherChannelLatest  = $registryLatest
    } elseif ($channel -eq 'npm') {
        $channelLatest       = $registryLatest
        $channelLatestSource = 'npm registry'
        if ($S.MiseTool) {
            $otherChannel       = 'mise'
            $otherChannelLatest = $miseRemoteLatest
        }
    }

    # Is there anything newer to act on, on the channel that is actually installed?
    $isLatest       = $null
    $behindPatch    = $null
    $channelVerdict = 'unknown'
    $actionable     = $false

    if ($version -and $channelLatest) {
        $isLatest = ($version -eq $channelLatest)
        $a = [regex]::Match($version, '^(\d+)\.(\d+)\.(\d+)')
        $b = [regex]::Match($channelLatest, '^(\d+)\.(\d+)\.(\d+)')
        if ($a.Success -and $b.Success -and
            $a.Groups[1].Value -eq $b.Groups[1].Value -and
            $a.Groups[2].Value -eq $b.Groups[2].Value) {
            $behindPatch = [int]$b.Groups[3].Value - [int]$a.Groups[3].Value
        }
        if ($isLatest) { $channelVerdict = 'up to date' }
        elseif ($behindPatch -gt 0) { $channelVerdict = "$behindPatch patch behind" }
        elseif ($channelLatest) { $channelVerdict = "behind ($version -> $channelLatest)" }
        $actionable = -not $isLatest
    } elseif ($version) {
        $channelVerdict = 'channel latest unavailable'
    }

    $crossChannelNewer = $null
    if ($otherChannelLatest -and $channelLatest) {
        $top = Get-TopVersion @($channelLatest, $otherChannelLatest)
        $crossChannelNewer = ($top -eq $otherChannelLatest)
    }

    # --- 11. config / state locations --------------------------------------
    $cfg = @()
    if ($name -eq 'claude') {
        $cfg += @($env:CLAUDE_CONFIG_DIR, (Join-Path $env:USERPROFILE '.claude'), (Join-Path $env:USERPROFILE '.claude.json'))
    } elseif ($name -eq 'codex') {
        $cfg += @($(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }))
    } elseif ($name -eq 'opencode') {
        $cfg += @(
            (Join-Path $env:USERPROFILE '.config\opencode'),
            (Join-Path $env:USERPROFILE '.local\share\opencode')
        )
    }
    $configHits = @()
    foreach ($p in $cfg) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p) {
            $it = Get-Item -LiteralPath $p
            if ($it.PSIsContainer) {
                $dirSz      = Get-DirBytes $p
                $configHits += [pscustomobject]@{ Path = $p; Kind = 'dir';  Bytes = $dirSz.Dedupe }
            } else {
                $configHits += [pscustomobject]@{ Path = $p; Kind = 'file'; Bytes = $it.Length }
            }
        } else {
            $configHits += [pscustomobject]@{ Path = $p; Kind = 'missing'; Bytes = $null }
        }
    }

    return [pscustomobject]@{
        Name            = $name
        Package         = $pkgName
        SelectedCommand = if ($selected) { $selected.Source } else { $null }
        ResolvedVia     = $resolvedVia
        Channel         = $channel
        Version         = $version
        RawVersion      = if ($rawVersion) { $rawVersion.Split("`n")[0] } else { $null }
        VersionError    = $versionError
        ExecutableRun   = $exeToRun
        PathHits        = @($cmds | ForEach-Object { $_.Source })
        OtherInstalls   = $otherInstalls
        PackageVersion  = if ($pkgJson) { $pkgJson.version } else { $null }
        NativeExe       = $nativeExe
        NativeExeBytes  = $nativeBytes
        PackageDir      = $pkgDir
        InstallBytes    = $installBytes
        InstallBytesNaive = $installBytesNaive
        InstallTime     = $installTime
        MiseInstall     = $miseInstall
        MiseVersion     = $miseVersion
        MiseRequested   = $miseRequested
        MiseResolvedHow = $miseResolvedHow
        MiseRemoteLatest = $miseRemoteLatest
        MiseRemoteError  = $miseRemoteError
        MiseRemoteCount  = $miseRemoteCount
        RegistryLatest  = $registryLatest
        RegistryError   = $registryError
        ChannelLatest   = $channelLatest
        ChannelLatestSource = $channelLatestSource
        OtherChannel        = $otherChannel
        OtherChannelLatest  = $otherChannelLatest
        CrossChannelNewer   = $crossChannelNewer
        ChannelVerdict  = $channelVerdict
        Actionable      = $actionable
        IsLatest        = $isLatest
        BehindPatch     = $behindPatch
        Shadowed        = $shadowed
        ConfigHits      = $configHits
        UpdateCommand   = $S.UpdateCmd
    }
}

# ===========================================================================
# Main
# ===========================================================================
$results = @()
foreach ($s in $Spec) {
    if ($Cli -contains $s.Name) { $results += Probe-Clr $s }
}

if ($Json) {
    [pscustomobject]@{ Environment = $envInfo; Clis = $results } | ConvertTo-Json -Depth 8
    if (@($results | Where-Object { -not $_.Version }).Count -gt 0) { exit 2 }
    if ($ExitIfBehind -and @($results | Where-Object { $_.Actionable }).Count -gt 0) { exit 3 }
    exit 0
}

Write-Output "================ probe-clis ================"
$envInfo | Format-List | Out-String -Width 200 | Write-Output

foreach ($r in $results) {
    Write-Output ("---------- {0} ----------" -f $r.Name)
    Write-Output ("  selectedCommand : {0}" -f $(if ($r.SelectedCommand) { $r.SelectedCommand } else { '- (not on PATH)' }))
    Write-Output ("  resolvedVia     : {0}" -f $r.ResolvedVia)
    Write-Output ("  channel         : {0}" -f $r.Channel)
    Write-Output ("  version         : {0}" -f $(if ($r.Version) { $r.Version } else { '(not resolved)' }))
    Write-Output ("  rawVersion      : {0}" -f $r.RawVersion)
    if ($r.VersionError) { Write-Output ("  versionError    : {0}" -f $r.VersionError) }
    Write-Output ("  executableRun   : {0}" -f $(if ($r.ExecutableRun) { $r.ExecutableRun } else { '- (none ran)' }))
    Write-Output ("  package         : {0}{1}" -f $r.Package, $(if ($r.PackageVersion) { '@' + $r.PackageVersion } else { '' }))
    Write-Output ("  nativeExe       : {0}" -f $(if ($r.NativeExe) { $r.NativeExe } else { '- (no npm layout)' }))
    if ($r.NativeExeBytes) { Write-Output ("  nativeExeBytes  : {0}" -f $r.NativeExeBytes) }
    if ($r.MiseInstall) { Write-Output ("  miseInstall     : {0}  [{1}]" -f $r.MiseInstall, $r.MiseResolvedHow) }
    if ($r.MiseVersion) { Write-Output ("  miseVersion     : {0} (requested: {1})" -f $r.MiseVersion, $r.MiseRequested) }
    Write-Output ("  installTime     : {0}" -f $(if ($r.InstallTime) { $r.InstallTime } else { '-' }))
    if ($r.InstallBytes) { Write-Output ("  installBytes    : {0}  (deduped, hardlinks once)" -f $r.InstallBytes) }
    if ($r.InstallBytesNaive -and $r.InstallBytesNaive -ne $r.InstallBytes) {
        Write-Output ("  installBytesNaive: {0}  (duplicate/hardlinked copies counted)" -f $r.InstallBytesNaive)
    }

    Write-Output "  --- update decision (channel-scoped) ---"
    Write-Output ("  channelLatest   : {0}" -f $(if ($r.ChannelLatest) { $r.ChannelLatest } else { if ($SkipRemote) { '(skipped)' } else { '(unavailable)' } }))
    $src = if ($SkipRemote) { '(skipped - remote lookups disabled)' }
           elseif ($r.ChannelLatestSource) { $r.ChannelLatestSource }
           else { '-' }
    if ($r.MiseRemoteCount) { $src = $src + "  [$($r.MiseRemoteCount) versions seen]" }
    Write-Output ("  channelSource   : {0}" -f $src)
    Write-Output ("  verdict         : {0}" -f $r.ChannelVerdict)
    Write-Output ("  actionable      : {0}" -f $r.Actionable)
    if ($r.Actionable) { Write-Output ("  updateCommand   : {0}" -f $r.UpdateCommand) }

    # Three states: true / false / unknown (comparison could not be made).
    if ($r.CrossChannelNewer -eq $true) {
        Write-Output ("  crossChannel    : {0} {1} is NEWER but UNREACHABLE via {2}" -f $r.OtherChannel, $r.OtherChannelLatest, $r.Channel)
        Write-Output "                    (informational only - the active channel cannot get there)"
    } elseif ($r.CrossChannelNewer -eq $false) {
        Write-Output ("  crossChannel    : {0} {1} (not newer)" -f $r.OtherChannel, $(if ($r.OtherChannelLatest) { $r.OtherChannelLatest } else { '(unknown)' }))
    } elseif ($r.OtherChannel) {
        Write-Output ("  crossChannel    : {0} (comparison unavailable)" -f $r.OtherChannel)
    }
    if ($r.Channel -eq 'mise') {
        Write-Output ("  registryLatest  : {0}  (npm, informational)" -f $(if ($r.RegistryLatest) { $r.RegistryLatest } else { if ($SkipRemote) { '(skipped)' } else { '(lookup failed)' } }))
    } else {
        Write-Output ("  registryLatest  : {0}" -f $(if ($r.RegistryLatest) { $r.RegistryLatest } else { if ($SkipRemote) { '(skipped)' } else { '(lookup failed)' } }))
    }
    if ($r.RegistryError) {
        Write-Output ("  registryError   : {0}" -f $r.RegistryError.Substring(0, [Math]::Min(200, $r.RegistryError.Length)))
    }
    if ($r.MiseRemoteError) { Write-Output ("  miseRemoteError : {0}" -f $r.MiseRemoteError) }

    if ($r.PathHits.Count -eq 0) {
        Write-Output "  pathHits        : (none - not on PATH)"
    } else {
        Write-Output ("  pathHits        : {0}" -f $r.PathHits.Count)
    }
    if ($r.Shadowed.Count -gt 0) {
        Write-Output ("  shadowed        : {0} duplicate install(s) lost the PATH race" -f $r.Shadowed.Count)
        foreach ($sh in $r.Shadowed) { Write-Output ("    [{0}] {1}" -f $sh.Channel, $sh.Base) }
    } elseif ($r.PathHits.Count -gt 1) {
        Write-Output "  shadowed        : (none)"
    }
    if ($r.OtherInstalls.Count -gt 0) {
        Write-Output ("  otherInstalls   : {0} install(s) NOT on PATH" -f $r.OtherInstalls.Count)
        foreach ($o in $r.OtherInstalls) { Write-Output ("    [{0} via {1}] {2}" -f $o.Channel, $o.How, $o.Path) }
    }

    Write-Output "  configHits      :"
    foreach ($c in $r.ConfigHits) {
        Write-Output ("    {0,-8} {1,12} {2}" -f $c.Kind, $(if ($c.Bytes) { $c.Bytes } else { '-' }), $c.Path)
    }
    Write-Output ""
}

Write-Output "---------------- summary ----------------"
Write-Output "  (verdict compares against the ACTIVE channel's latest, not every registry)"
foreach ($r in $results) {
    $via = if ($r.ResolvedVia -ne 'path') { '  <{0}>' -f $r.ResolvedVia } else { '' }
    $flag = if ($r.CrossChannelNewer) { "  [{0} {1} elsewhere]" -f $r.OtherChannel, $r.OtherChannelLatest } else { '' }
    Write-Output ("  {0,-9} {1,-8} {2,-12} {3,-24} {4}{5}" -f $r.Name, $r.Channel, $r.Version, $r.ChannelVerdict, $via, $flag)
}

Write-Output ""
Write-Output "DONE"
if (@($results | Where-Object { -not $_.Version }).Count -gt 0) { exit 2 }
if ($ExitIfBehind -and @($results | Where-Object { $_.Actionable }).Count -gt 0) { exit 3 }
exit 0
