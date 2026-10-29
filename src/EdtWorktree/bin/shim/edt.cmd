@echo off
rem Shim: version-independent launcher; finds the highest installed EdtWorktree.
pwsh -NoProfile -File "%~dp0edt.ps1" %*
exit /b %ERRORLEVEL%
