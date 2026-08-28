<#
.SYNOPSIS
    Logs off interactive sessions that have been idle longer than a threshold,
    but only takes action after a configured start hour (default 8 PM).

.DESCRIPTION
    Intended to be run repeatedly (e.g. every 30 minutes) by a Scheduled Task
    between 8:00 PM and midnight. Each run:
      1. Exits immediately if the current hour is before -StartHour.
      2. Parses `quser` to find every session and its idle time.
      3. Logs off (via `logoff.exe`) any session idle longer than -ThresholdMinutes.

    Must run as a principal with rights to log off other users' sessions
    (LOCAL SYSTEM works;).

.PARAMETER ThresholdMinutes
    Idle time in minutes before a session is logged off. Default 180 (3 hours).

.PARAMETER StartHour
    Hour (24h clock) after which the script is allowed to act. Default 20 (8 PM).

.PARAMETER ExcludeUsers
    Usernames to never log off (e.g. a service or admin account), case-insensitive.

.PARAMETER WhatIf
    Report what would happen without actually logging anyone off. Use this first
    to sanity-check parsing and thresholds on your machine before enabling for real.

.OUTPUTS
    Writes a timestamped line per session evaluated, and per logoff performed,
    to IdleLogoff.log next to this script.
#>

param(
    [int]$ThresholdMinutes = 180,
    [int]$StartHour = 20,
    [string[]]$ExcludeUsers = @(),
    [switch]$WhatIf
)

$logPath = Join-Path $PSScriptRoot "IdleLogoff.log"

function Write-Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    Add-Content -Path $logPath -Value $line
    Write-Output $line
}

function Convert-IdleTimeToMinutes {
    param([string]$IdleString)
    $IdleString = $IdleString.Trim()
    if ($IdleString -eq '.' -or $IdleString -eq '') {
        return 0
    }
    if ($IdleString -match '^(\d+)\+(\d{1,2}):(\d{2})$') {
        # days+hh:mm
        return ([int]$matches[1] * 24 * 60) + ([int]$matches[2] * 60) + [int]$matches[3]
    }
    if ($IdleString -match '^(\d{1,2}):(\d{2})$') {
        # hh:mm
        return ([int]$matches[1] * 60) + [int]$matches[2]
    }
    if ($IdleString -match '^\d+$') {
        # bare minutes (rare, but seen on some builds)
        return [int]$IdleString
    }
    return 0
}

$now = Get-Date
if ($now.Hour -lt $StartHour) {
    Write-Log "Before $($StartHour):00 (now $($now.ToString('HH:mm'))) - skipping."
    exit 0
}

$quserOutput = quser 2>$null
if (-not $quserOutput -or $quserOutput.Count -le 1) {
    Write-Log "No active sessions reported by quser."
    exit 0
}

# Skip the header row. Match each session line by anchoring on the fixed
# tokens (session ID, state, idle time, logon date) rather than fixed
# column widths, since quser's SESSIONNAME field is blank for disconnected
# sessions and shifts columns around.
$pattern = '^\>?(?<rest>.+?)\s+(?<id>\d+)\s+(?<state>Active|Disc)\s+(?<idle>\.|(?:\d+\+)?\d{1,2}:\d{2}|\d+)\s+(?<logon>\d{1,2}/\d{1,2}/\d{4}.*)$'

foreach ($rawLine in ($quserOutput | Select-Object -Skip 1)) {
    $line = $rawLine.TrimEnd()
    if ($line -notmatch $pattern) {
        Write-Log "Could not parse line, skipping: '$line'"
        continue
    }

    $sessionId  = $matches['id']
    $state      = $matches['state']
    $idleStr    = $matches['idle']
    $idleMin    = Convert-IdleTimeToMinutes $idleStr
    $userName   = ($matches['rest'].Trim() -split '\s+')[0]

    Write-Log "Session $sessionId user=$userName state=$state idle=$idleStr (${idleMin}m)"

    if ($ExcludeUsers -contains $userName) {
        Write-Log "  -> $userName is in -ExcludeUsers, skipping."
        continue
    }

    if ($idleMin -gt $ThresholdMinutes) {
        if ($WhatIf) {
            Write-Log "  -> WOULD log off session $sessionId ($userName), idle ${idleMin}m > ${ThresholdMinutes}m threshold. (-WhatIf, no action taken)"
        }
        else {
            Write-Log "  -> Logging off session $sessionId ($userName), idle ${idleMin}m > ${ThresholdMinutes}m threshold."
            logoff $sessionId
        }
    }
}
