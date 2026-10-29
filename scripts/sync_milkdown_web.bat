@echo off
setlocal enabledelayedexpansion

set "REPO_ROOT=%~dp0.."
for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"
set "WEB_DIR=%REPO_ROOT%\web\milkdown"
set "WEB_DIST_DIR=%WEB_DIR%\dist"
set "WEB_DIST=%WEB_DIST_DIR%\index.html"
set "WEB_ASSET_DIR=%REPO_ROOT%\assets\milkdown_web"
set "WEB_ASSET=%WEB_ASSET_DIR%\index.html"

echo [sync] Checking Node.js environment...
where node >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Node.js is not installed or not in PATH.
  exit /b 1
)

if not exist "%WEB_DIR%\package.json" (
  echo [ERROR] Missing web package.json: %WEB_DIR%\package.json
  exit /b 1
)

echo [sync] Building Milkdown web bundle...
cd /d "%WEB_DIR%" || exit /b 1

call npm ci || exit /b 1
call npm run build || exit /b 1

if not exist "%WEB_DIST%" (
  echo [ERROR] Missing built file: %WEB_DIST%
  exit /b 1
)

if not exist "%WEB_ASSET_DIR%" mkdir "%WEB_ASSET_DIR%" || exit /b 1
del /Q "%WEB_ASSET_DIR%\*.*" >nul 2>&1
xcopy /E /I /Y "%WEB_DIST_DIR%" "%WEB_ASSET_DIR%" >nul || exit /b 1
cd /d "%REPO_ROOT%" || exit /b 1

echo [sync] Synced web bundle to: %WEB_ASSET_DIR%
exit /b 0
