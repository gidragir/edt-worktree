@echo off
rem Shim: run edt from any shell (cmd, nushell, bash, agents). Logic is in edt.ps1.
pwsh -NoProfile -File "%~dp0edt.ps1" %*
exit /b %ERRORLEVEL%
