' Truly-hidden launcher for bcp_watcher.ps1, used by the "BCP PBI Watcher"
' scheduled task. See bcp_publish_silent.vbs for why WScript.Shell.Run with
' windowstyle=0 is used instead of PowerShell's own -WindowStyle Hidden.
Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File """ & scriptDir & "\bcp_watcher.ps1"""
objShell.Run cmd, 0, False
