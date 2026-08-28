# win_idle_user_auto_logout
Powershell for system admins who can't stand having shared pc users just disconnect


Copy or Download the Idle-logoff script — review before installing

## Installing it
1. Test it dry-run first, from an elevated PowerShell prompt, to confirm parsing works on your machine and no one gets surprised:

   `powershell -ExecutionPolicy Bypass -File "C:\Path\To\IdleLogoff.ps1" -WhatIf -StartHour 0`
   -StartHour 0 bypasses the time gate so you can test right now regardless of the clock; drop it once you've verified. Check the IdleLogoff.log written next to the script — it lists every session it saw, its parsed idle time, and what it would have done.

2. Move the script somewhere permanent, e.g. C:\Scripts\IdleLogoff.ps1, then register the scheduled task yourself (elevated PowerShell):

   `$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\IdleLogoff.ps1"'
$trigger   = New-ScheduledTaskTrigger -Daily -At 8:00PM
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At 8:00PM -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Hours 4)).Repetition
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "IdleLogoff" -Action $action -Trigger $trigger -Principal $principal -Description "Logs off sessions idle >3h, 8PM-midnight"`

This runs the check every 15 minutes from 8:00 PM to midnight, as SYSTEM (needed to log off other users' sessions), regardless of who's logged in. Adjust -RepetitionDuration if you want it to keep checking past midnight.

3. Exclude any accounts that should never be force-logged-off (e.g. an admin account you leave logged in for RDP maintenance) by adding -ExcludeUsers "svc_backup","admin" to the task's argument string.
