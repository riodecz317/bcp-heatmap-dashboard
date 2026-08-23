' Truly-hidden launcher for bcp_bridge.ps1, started by bcp_watcher.ps1 when
' Power BI Desktop comes online. Unlike bcp_publish_silent.vbs (a one-shot
' script that runs to completion), bcp_bridge.ps1 is a long-running listener
' loop -- WScript.Shell.Run's third argument (False = don't wait) lets it
' keep running detached in the background with no visible window.
Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File """ & scriptDir & "\bcp_bridge.ps1"""
objShell.Run cmd, 0, False
