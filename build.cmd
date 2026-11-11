@echo off
setlocal enabledelayedexpansion

rem Build a single-file Windows exe (PCK embedded).
rem   out: build\poker-pusher-<tag>-windows-x86_64.exe
rem Set GODOT to override the engine path.

set "PROJ=%~dp0"

if "%GODOT%"=="" (
    for %%g in (godot.exe Godot_v4.7.2-stable_win64_console.exe) do (
        if "!GODOT!"=="" (
            for /f "delims=" %%p in ('where %%g 2^>nul') do (
                if "!GODOT!"=="" set "GODOT=%%p"
            )
        )
    )
)
if "%GODOT%"=="" if exist "D:\godex\Godot_v4.7.2-stable_win64_console.exe" set "GODOT=D:\godex\Godot_v4.7.2-stable_win64_console.exe"

if "%GODOT%"=="" (
    echo [ERR] Godot not found. Set GODOT=C:\path\to\Godot_v4.7.2-stable_win64_console.exe
    exit /b 1
)

rem Version = nearest git tag, fallback v0.0.0
set "GIT="
where git >nul 2>nul && set "GIT=git"
if "%GIT%"=="" if exist "C:\Program Files\Git\cmd\git.exe" set "GIT=C:\Program Files\Git\cmd\git.exe"
set "TAG="
if not "%GIT%"=="" (
    if not exist "%PROJ%build" mkdir "%PROJ%build"
    "%GIT%" -C "%PROJ%." describe --tags --abbrev=0 > "%PROJ%build\.tag" 2>nul
    if exist "%PROJ%build\.tag" set /p TAG=<"%PROJ%build\.tag"
    if exist "%PROJ%build\.tag" del /q "%PROJ%build\.tag"
)
if "%TAG%"=="" set "TAG=v0.0.0"

if not exist "%PROJ%build" mkdir "%PROJ%build"

set "OUT=build\poker-pusher-%TAG%-windows-x86_64.exe"
if exist "%PROJ%%OUT%" del /q "%PROJ%%OUT%"

echo [..] engine: %GODOT%
echo [..] version: %TAG%
echo [..] export: %OUT%
"%GODOT%" --headless --path "%PROJ%." --export-release "Windows Desktop" "%OUT%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo [ERR] export failed, exit=%RC%
    exit /b %RC%
)

if not exist "%PROJ%%OUT%" (
    echo [ERR] export reported success but %OUT% is missing
    exit /b 1
)
echo [OK] %PROJ%%OUT%
exit /b 0
