@echo off
cd /d "%~dp0"
call flutter clean
call powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0increment_version.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%

call flutter build windows --release
if errorlevel 1 exit /b %ERRORLEVEL%

if not exist "build\windows\x64\runner\Release\steamcmd_worker.exe" exit /b 1
if not exist "build\windows\x64\runner\Release\steamcmd_hook.dll" exit /b 1

call "C:\Program Files\Inno Setup 7\ISCC.exe" .\build.iss
exit /b %ERRORLEVEL%
