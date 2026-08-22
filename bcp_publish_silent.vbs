' Truly-hidden launcher for bcp_publish.ps1, used by the "BCP Dashboard
' Auto-Publish" scheduled task. PowerShell's own -WindowStyle Hidden still
' briefly flashes a console window when launched by Task Scheduler in an
' interactive session; WScript.Shell.Run's windowstyle=0 never creates a
' visible window in the first place, so there's nothing to flash.
Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File """ & scriptDir & "\bcp_publish.ps1"""
objShell.Run cmd, 0, False
