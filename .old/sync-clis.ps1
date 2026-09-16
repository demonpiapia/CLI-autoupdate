#Requires -Version 7.4
<#
.SYNOPSIS
    Copy the three CLI exes to their fixed caller-side locations.

.DESCRIPTION
    After an update is confirmed, copy the freshly-installed claude / codex /
    opencode native exe over the three fixed entry-point files so the user can
    invoke the CLIs from stable paths that don't depend on mise shims, the
    MISE_* environment, or PATH ordering:

        D:\AI\Programs\Claude-Code-CLI\claude.exe
        D:\AI\Programs\Codex\CLI\codex.exe
        D:\AI\Programs\opencode\CLI\opencode.exe

    Sources are resolved by PURE FILESYSTEM SCAN (cli-common.ps1:
    Resolve-MiseExeByScan / npm prefix) — no mise subprocess, no PATH, no
    MISE_* env. So this script runs identically in the Cherry agent, an
    external terminal, or a scheduled task, and cannot hang.

    DEFAULT MODE IS DRY RUN: reports what would be copied (source bytes,
    target bytes, action = copy/skip) and changes nothing. -Execute copies.

    Guard rail in Execute mode (hard stop, not warning):
      * a target exe is currently running (locked) — Windows cannot replace an
        in-use .exe. Close the CLI session first.

.OUTPUTS
    Human-readable report on stdout.

.EXITCODES
    0  = all three already in sync (source == target bytes+mtime), nothing done
    10 = dry run, at least one copy is pending
    11 = copies applied and verified (byte counts match)
    2  = a source could not be resolved (CLI not installed?)
    3  = a copy failed or post-copy verification failed

.EXAMPLE
    pwsh -NoProfile -File sync-clis.ps1
    Dry run.

.EXAMPLE
    pwsh -NoProfile -File sync-clis.ps1 -Execute
    Copy all three, verify byte counts.
#>
param(
    [switch]$Execute,
    [int]$MinFreeMB = 1024
)

. (Join-Path $PSScriptRoot 'cli-common.ps1')

$mode = if ($Execute) { 'EXECUTE' } else { 'DRY RUN' }
Write-Head 'sync CLIs to caller-side paths' $mode

# source resolver + fixed target per CLI
$targets = [ordered]@{
    claude   = 'D:\AI\Programs\Claude-Code-CLI\claude.exe'
    codex    = 'D:\AI\Programs\Codex\CLI\codex.exe'
    opencode = 'D:\AI\Programs\opencode\CLI\opencode.exe'
}

$rows = @()
$pending = 0
$failed  = 0

foreach ($name in $targets.Keys) {
    $tgt = $targets[$name]
    $inst = Get-InstalledExe -Name $name
    if (-not $inst -or -not $inst.Exe -or -not (Test-Path -LiteralPath $inst.Exe)) {
        Write-Output ("  {0,-9}: source NOT RESOLVED (is {0} installed?)" -f $name)
        $failed++
        $rows += [pscustomobject]@{ Name=$name; Action='FAIL'; Reason='source unresolved' }
        continue
    }
    $srcInfo = Get-Item -LiteralPath $inst.Exe
    # Backstop: never sync a stub. opencode-ai can leave bin\opencode.exe as a
    # ~479 B placeholder when its platform optionalDep isn't fetched (see
    # update-opencode.ps1). A real CLI exe is > 1 MB. Refuse below that.
    if ($srcInfo.Length -lt 1MB) {
        Write-Output ("  {0,-9}: REFUSE source {1} B (< 1 MB — stub/broken, not a real binary)" -f $name, $srcInfo.Length)
        $failed++
        $rows += [pscustomobject]@{ Name=$name; Action='FAIL'; Reason="source stub ($($srcInfo.Length) B)" }
        continue
    }
    $tgtExists = Test-Path -LiteralPath $tgt
    $tgtInfo = if ($tgtExists) { Get-Item -LiteralPath $tgt } else { $null }

    $action = 'copy'
    $reason = ''
    if ($tgtExists -and $tgtInfo.Length -eq $srcInfo.Length -and $tgtInfo.LastWriteTimeUtc -eq $srcInfo.LastWriteTimeUtc) {
        $action = 'skip'
        $reason = 'already in sync (bytes+mtime match)'
    }
    elseif (-not $tgtExists) {
        $action = 'copy'
        $reason = 'target missing'
    }

    Write-Output ("  {0,-9}: {1}  ({2} B)" -f $name, $inst.Version, $srcInfo.Length)
    Write-Output ("            source : {0}" -f $inst.Exe)
    Write-Output ("            target : {0}" -f $tgt)
    if ($tgtExists) {
        Write-Output ("            target : {0} B  (current)" -f $tgtInfo.Length)
    }
    Write-Output ("            action : {0}  {1}" -f $action, $reason)

    if ($action -eq 'copy') { $pending++ }
    $rows += [pscustomobject]@{ Name=$name; Action=$action; Reason=$reason; Src=$inst.Exe; Tgt=$tgt; SrcBytes=$srcInfo.Length }
}

if ($failed) {
    Write-Output ''
    Write-Output "  aborting: $failed source(s) unresolved"
    exit 2
}
if (-not $pending) {
    Write-Output ''
    Write-Output '  all three already in sync — nothing to do.'
    exit 0
}

Write-Output ''
Write-Output ("  {0} copy(ies) pending." -f $pending)

if (-not $Execute) {
    Write-Output '  DRY RUN - nothing changed. Re-run with -Execute to copy.'
    exit 10
}

# ---- Execute: copy each pending target -----------------------------------
foreach ($r in $rows) {
    if ($r.Action -ne 'copy') { continue }
    Write-Output ''
    Write-Output ("  copying {0} ..." -f $r.Name)

    # guard: target locked?
    if (Test-Path -LiteralPath $r.Tgt) {
        $locked = Test-FileLocked -Path $r.Tgt
        Write-Output ("    target lock : {0}" -f $(if ($locked) { 'LOCKED' } else { 'free' }))
        if ($locked) {
            Write-Output ("    REFUSING: {0} is in use. Close the running {0} session, re-run." -f $r.Name)
            exit 3
        }
    }

    # guard: destination drive headroom
    $tDir = Split-Path $r.Tgt -Parent
    if (-not (Test-Path -LiteralPath $tDir)) {
        try { New-Item -ItemType Directory -Path $tDir -Force | Out-Null } catch {
            Write-Output "    REFUSING: cannot create target dir $tDir : $($_.Exception.Message)"
            exit 3
        }
    }
    $free = Get-FreeBytes -Path $tDir
    $need = [long]$MinFreeMB * 1MB
    if ($free -ne $null -and $free -lt $need) {
        $freeMB = [int]($free / 1MB)
        Write-Output "    REFUSING: only $freeMB MB free on target drive (need $MinFreeMB)."
        exit 3
    }

    try {
        Copy-Item -LiteralPath $r.Src -Destination $r.Tgt -Force -ErrorAction Stop
    }
    catch {
        Write-Output "    FAILED copy: $($_.Exception.Message)"
        exit 3
    }

    $verify = Get-Item -LiteralPath $r.Tgt
    if ($verify.Length -ne $r.SrcBytes) {
        Write-Output ("    FAILED verify: target {0} B != source {1} B" -f $verify.Length, $r.SrcBytes)
        exit 3
    }
    Write-Output ("    verified : {0} B" -f $verify.Length)
}

Write-Output ''
Write-Output '  DONE - all copies applied and byte-verified.'
exit 11
