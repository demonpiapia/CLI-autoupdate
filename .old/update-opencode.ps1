#Requires -Version 7.4
<#
.SYNOPSIS
    Upgrade opencode CLI to the latest STABLE version on npm.

.DESCRIPTION
    Self-contained: no probe-clis.ps1 dependency. Detection is inline via
    cli-common.ps1 (npm prefix scan for the installed exe + npm view for the
    registry latest), and EVERY subprocess goes through Invoke-Proc — the
    deadlock-safe runner with a hard timeout + Kill. So this script cannot hang
    the way the old probe-spawning version could.

    Channel scope: opencode's active channel is npm (package opencode-ai).
    mise is NOT consulted for opencode. Target = the dist-tag 'version' (latest
    stable) on the public npm registry.

    Upgrade command: `npm install -g opencode-ai@<target>`. The caller-side
    exe in D:\AI\Programs\opencode\CLI is NOT this script's job — run
    sync-clis.ps1 -Execute after a successful upgrade.

    DEFAULT MODE IS DRY RUN. Pass -Execute to upgrade.

    Guard rails in Execute mode (hard stops):
      * installed exe locked (opencode running);
      * destination drive below -MinFreeMB free;
      * target is a prerelease (stable-only policy);
      * explicit -TargetVersion refused if it is not the registry latest
        (this updater follows latest only; pinning an older one is a downgrade
        and out of scope — use `npm install -g opencode-ai@<ver>` directly).

.OUTPUTS
    Human-readable report on stdout.

.EXITCODES
    0  = up to date / nothing to do (also: dry run with nothing pending)
    10 = dry run, an update IS available
    11 = upgrade applied and verified
    2  = decision failed: installed version or registry latest unreadable
    3  = upgrade attempted and failed, or verification failed

.EXAMPLE
    pwsh -NoProfile -File update-opencode.ps1
    pwsh -NoProfile -File update-opencode.ps1 -Execute
#>
param(
    [switch]$Execute,
    [string]$TargetVersion,
    [switch]$SkipRemote,
    [int]$MinFreeMB = 1024
)

. (Join-Path $PSScriptRoot 'cli-common.ps1')

$Name   = 'opencode'
$Pkg    = 'opencode-ai'
$PrereleaseRe = '(alpha|beta|rc|dev|nightly|canary|pre)'

$mode = if ($Execute) { 'EXECUTE' } else { 'DRY RUN' }
Write-Head "$Name upgrade (npm, stable only)" $mode

# ---- detect installed -----------------------------------------------------
$inst = Get-InstalledExe -Name $Name
if (-not $inst -or -not $inst.Exe) {
    Write-Output "  aborting: installed exe could not be resolved (is $Name installed via npm?)"
    exit 2
}
$installed = $inst.Version
$exeHealthy = [bool]$inst.ExeHealthy
Write-Output ("  installed       : {0}" -f $(if ($installed) { $installed } else { '(version unreadable)' }))
Write-Output ("  installed exe   : {0}" -f $inst.Exe)
Write-Output ("  package         : {0}" -f $Pkg)
Write-Output ("  exe healthy     : {0}" -f $(if ($exeHealthy) { 'yes' } else { 'NO (stub/broken — will force reinstall)' }))

if (-not $installed) {
    Write-Output "  aborting: installed version unreadable (package.json missing?)"
    exit 2
}

# ---- registry latest ------------------------------------------------------
$target = $TargetVersion
$source = 'explicit -TargetVersion'
if (-not $target) {
    if ($SkipRemote) {
        Write-Output "  nothing to do  : -SkipRemote set, no registry latest available"
        exit 0
    }
    $target = Get-NpmRegistryLatest -Pkg $Pkg
    $source = "npm view $Pkg version (latest stable)"
}

Write-Output ("  registry latest : {0}  ({1})" -f $(if ($target) { $target } else { '(none)' }), $source)

if (-not $target) {
    Write-Output "  nothing to do  : no stable target on the npm registry"
    exit 2
}
if ($exeHealthy -and $installed -eq $target) {
    Write-Output "  nothing to do  : already at $target and exe healthy"
    exit 0
}
if ($target -match $PrereleaseRe) {
    Write-Output "  nothing to do  : target '$target' is a prerelease; policy is stable-only"
    exit 0
}

# refuse an explicit non-latest target: this updater follows latest only.
if ($TargetVersion) {
    $regLatest = Get-NpmRegistryLatest -Pkg $Pkg
    if ($regLatest -and $target -ne $regLatest) {
        Write-Output ''
        Write-Output "  REFUSING: target '$target' is not the registry latest ('$regLatest')."
        Write-Output "           This updater follows latest only. To pin a version:"
        Write-Output "             npm install -g $Pkg@$target"
        exit 0
    }
    if (-not $regLatest) {
        Write-Output "  aborting: cannot confirm '$target' is the registry latest (npm view failed)"
        exit 2
    }
}

$repairNeeded = -not $exeHealthy
Write-Output ''
if ($repairNeeded -and $installed -eq $target) {
    Write-Output "  ACTIONABLE: exe is a broken stub though version matches $target — force reinstall"
} else {
    Write-Output "  ACTIONABLE: $installed -> $target"
}

$npm = Get-NpmCmd
if (-not $npm) {
    Write-Output "  aborting: npm.cmd not found on PATH or under npm prefix"
    exit 2
}
# --force re-fetches the optional platform binary (opencode-windows-x64) whose
# absence leaves bin\opencode.exe as a ~479 B stub. Always use --force on repair;
# on a normal version bump the platform binary for the new version is fetched fresh.
$installArgs = @('install', '-g', "$Pkg@$target")
if ($repairNeeded) { $installArgs += '--force' }
Write-Output ('  would run     : "{0}" {1}' -f $npm, ($installArgs -join ' '))
Write-Output '                 (Invoke-Proc routes npm.cmd via cmd.exe /c — direct .NET'
Write-Output '                  ProcessStartInfo on a .cmd mangles args, exit 1; verified 0916)'

if (-not $Execute) {
    Write-Output ''
    Write-Output '  DRY RUN - nothing changed. Re-run with -Execute to upgrade.'
    exit 10
}

# ---- guard rail 1: running instance cannot be replaced --------------------
$locked = Test-FileLocked -Path $inst.Exe
Write-Output ("  exe lock       : {0}" -f $(if ($locked) { 'LOCKED' } else { 'free' }))
if ($locked) {
    Write-Output ''
    Write-Output "  REFUSING: $inst.Exe is in use (an opencode session is running). Close it first."
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
$r = Invoke-Proc -FilePath $npm -Arguments $installArgs -TimeoutMs 600000
if (-not $r.Ok) {
    Write-Output ("  FAILED: {0}" -f $r.Error)
    exit 3
}
if ($r.ExitCode -ne 0) {
    $tail = ($r.Output -split "`r?`n" | Select-Object -Last 10) -join "`n"
    Write-Output ("  FAILED: npm exit $($r.ExitCode)")
    if ($tail) { Write-Output ("  npm output (tail):`n$tail") }
    if ($r.Error) { Write-Output ("  npm stderr (tail):`n" + (($r.Error -split "`r?`n" | Select-Object -Last 6) -join "`n")) }
    exit 3
}

# ---- post-upgrade verify --------------------------------------------------
$inst2 = Get-InstalledExe -Name $Name
$after = if ($inst2) { $inst2.Version } else { $null }
$afterHealthy = if ($inst2) { [bool]$inst2.ExeHealthy } else { $false }
Write-Output ''
Write-Output ("  verified       : {0}  exe healthy: {1}  (target was {2})" -f $(if ($after) { $after } else { '(unreadable)' }), $(if ($afterHealthy) { 'yes' } else { 'NO' }), $target)
if (-not $afterHealthy) {
    Write-Output '  FAILED: exe is still a broken stub after reinstall (platform binary not fetched)'
    Write-Output '  manual repair: npm install -g opencode-ai@<v> --force  (in a real shell)'
    exit 3
}
if ($after -ne $target) {
    Write-Output '  FAILED: installed version does not match the target'
    Write-Output '  (npm may have resolved a different version; re-run to re-decide)'
    exit 3
}
Write-Output '  DONE - update applied and verified.'
Write-Output '  Next: run sync-clis.ps1 -Execute to refresh the D:\AI\Programs caller-side copy.'
exit 11
