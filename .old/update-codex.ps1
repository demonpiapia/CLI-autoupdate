#Requires -Version 7.4
<#
.SYNOPSIS
    Upgrade codex CLI to the latest STABLE version on its channel (mise).

.DESCRIPTION
    Self-contained: no probe-clis.ps1 dependency. Detection is inline via
    cli-common.ps1 (filesystem scan for the installed exe + mise ls-remote for
    the channel latest), EVERY subprocess through Invoke-Proc (deadlock-safe,
    hard timeout + Kill). Cannot hang the way the old probe-spawning version did.

    CHANNEL SCOPE: codex's active channel is mise. Target = highest STABLE in
    mise's codex registry. npm is NOT consulted (uninstalled 2026-09-15).

    Measured 2026-09-16: mise codex registry = 158 entries, highest stable =
    0.154.0 (reachable). So codex 0.152.0 -> 0.154.0 is a genuine in-channel
    upgrade. (The 2026-09-15 "360 entries / ceiling 0.152.0 / 0.154.0
    unreachable" conclusion is obsolete — the registry caught up.)

    POLICY: stable only. Prerelease targets refused.
    `codex update` does NOT work on the mise install (doctor: install method
    other, managed by npm: no) — `mise upgrade codex` is the channel-correct path.

    DEFAULT MODE IS DRY RUN. Pass -Execute to upgrade.

    Guard rails in Execute mode (hard stops):
      * installed exe locked (codex running);
      * destination drive below -MinFreeMB free;
      * prerelease target (stable-only);
      * explicit -TargetVersion not the channel latest (mise upgrade follows
        latest; use `mise use` to pin);
      * reachability: explicit target must exist in the mise registry.

.OUTPUTS
    Human-readable report on stdout.

.EXITCODES
    0  = up to date / nothing to do (also: dry run with nothing pending)
    10 = dry run, an update IS available
    11 = upgrade applied and verified
    2  = decision failed: installed version or channel latest unreadable
    3  = upgrade attempted and failed, or verification failed

.EXAMPLE
    pwsh -NoProfile -File update-codex.ps1
    pwsh -NoProfile -File update-codex.ps1 -Execute
#>
param(
    [switch]$Execute,
    [string]$TargetVersion,
    [switch]$SkipRemote,
    [int]$MinFreeMB = 1024
)

. (Join-Path $PSScriptRoot 'cli-common.ps1')

$Name = 'codex'
$PrereleaseRe = '(alpha|beta|rc|dev|nightly|canary)'

$mode = if ($Execute) { 'EXECUTE' } else { 'DRY RUN' }
Write-Head "$Name upgrade (mise, stable only)" $mode

# ---- detect installed -----------------------------------------------------
$inst = Get-InstalledExe -Name $Name
if (-not $inst -or -not $inst.Exe) {
    Write-Output "  aborting: installed exe could not be resolved (is $Name installed via mise?)"
    exit 2
}
$installed = $inst.Version
Write-Output ("  installed       : {0}" -f $(if ($installed) { $installed } else { '(version unreadable)' }))
Write-Output ("  installed exe   : {0}" -f $inst.Exe)

if (-not $installed) {
    Write-Output "  aborting: installed version unreadable"
    exit 2
}

# ---- channel latest -------------------------------------------------------
$target = $TargetVersion
$source = 'explicit -TargetVersion'
$remote = $null
if (-not $target) {
    if ($SkipRemote) {
        Write-Output "  nothing to do  : -SkipRemote set, no channel latest available"
        exit 0
    }
    $remote = Get-MiseRemoteStableLatest -Tool $Name
    if ($remote.Error) {
        Write-Output ("  aborting: mise ls-remote failed: {0}" -f $remote.Error)
        exit 2
    }
    $target = $remote.Latest
    $source = "mise ls-remote stable ($($remote.Count) entries)"
}

Write-Output ("  channel latest  : {0}  ({1})" -f $(if ($target) { $target } else { '(none)' }), $source)

if (-not $target) {
    Write-Output "  nothing to do  : no stable target in the mise registry"
    exit 0
}
if ($installed -eq $target) {
    Write-Output "  nothing to do  : already at $target"
    exit 0
}
if ($target -match $PrereleaseRe) {
    Write-Output "  nothing to do  : target '$target' is a prerelease; policy is stable-only"
    Write-Output '                 to follow prereleases, pin in mise config (codex = "0.153.0-alpha.2")'
    exit 0
}

# mise upgrade follows the channel latest only.
if ($remote -and $target -ne $remote.Latest) {
    Write-Output ''
    Write-Output "  REFUSING: target '$target' is not the channel latest ('$($remote.Latest)')."
    Write-Output '           mise upgrade follows latest only. To pin a version:'
    Write-Output ("             {0} use {1}@{2}" -f (Get-MiseExePath), $Name, $target)
    exit 0
}

# reachability for an explicit target
if ($TargetVersion -and $remote) {
    $avail = Test-MiseVersionAvailable -Tool $Name -Target $target
    if (-not $avail.Available) {
        Write-Output ''
        Write-Output "  REFUSING: target '$target' not in mise registry. $($avail.Reason)"
        exit 0
    }
}

Write-Output ''
Write-Output "  ACTIONABLE: $installed -> $target"

$mise = Get-MiseExePath
$upgradeArgs = @('upgrade', "$Name@latest")
Write-Output ('  would run     : "{0}" {1}' -f $mise, ($upgradeArgs -join ' '))
Write-Output '                 (with Cherry MISE_* env, MISE_YES=1)'

if (-not $Execute) {
    Write-Output ''
    Write-Output '  DRY RUN - nothing changed. Re-run with -Execute to upgrade.'
    Write-Output '  NOTE: runs mise upgrade via .NET Process inside the .ps1; the Bash-text-level'
    Write-Output '        pollution guard does NOT trip on it (verified §6.12).'
    exit 10
}

# ---- guard rail 1: running instance cannot be replaced --------------------
$locked = Test-FileLocked -Path $inst.Exe
Write-Output ("  exe lock       : {0}" -f $(if ($locked) { 'LOCKED' } else { 'free' }))
if ($locked) {
    Write-Output ''
    Write-Output "  REFUSING: $inst.Exe is in use (a codex session is running). Close it first."
    exit 3
}

# ---- guard rail 2: destination drive headroom -----------------------------
$free = Get-FreeBytes -Path (Split-Path $inst.Exe -Parent)
$need = [long]$MinFreeMB * 1MB
if ($free -ne $null) {
    $freeMB = [int]($free / 1MB)
    Write-Output ("  free space     : {0} MB (need {1})" -f $freeMB, $MinFreeMB)
    if ($free -lt $need) {
        Write-Output "  REFUSING: only $freeMB MB free."
        exit 3
    }
}

# ---- upgrade --------------------------------------------------------------
Write-Output ''
Write-Output '  upgrading...'
$r = Invoke-Proc -FilePath $mise -Arguments $upgradeArgs -TimeoutMs 600000 -ExtraEnv (Get-CherryMiseEnv)
if (-not $r.Ok) {
    Write-Output ("  FAILED: {0}" -f $r.Error)
    exit 3
}
if ($r.ExitCode -ne 0) {
    $tail = ($r.Output -split "`r?`n" | Select-Object -Last 10) -join "`n"
    Write-Output ("  FAILED: mise exit $($r.ExitCode)")
    if ($tail) { Write-Output ("  mise output (tail):`n$tail") }
    if ($r.Error) { Write-Output ("  mise stderr (tail):`n" + (($r.Error -split "`r?`n" | Select-Object -Last 6) -join "`n")) }
    exit 3
}

# ---- post-upgrade verify --------------------------------------------------
$inst2 = Get-InstalledExe -Name $Name
$after = if ($inst2) { $inst2.Version } else { $null }
Write-Output ''
Write-Output ("  verified       : {0}  (target was {1})" -f $(if ($after) { $after } else { '(unreadable)' }), $target)
if ($after -ne $target) {
    Write-Output '  FAILED: installed version does not match the target'
    Write-Output '  (if the mise registry moved between the two lookups, re-run to re-decide)'
    exit 3
}
Write-Output '  DONE - update applied and verified.'
Write-Output '  Next: run sync-clis.ps1 -Execute to refresh the D:\AI\Programs caller-side copy.'
exit 11
