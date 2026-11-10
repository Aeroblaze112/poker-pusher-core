@echo off
setlocal enabledelayedexpansion

rem 导出 Windows 单文件 exe（PCK 内嵌），产物名带版本与平台：
rem   build\poker-pusher-v0.1.0-windows-x86_64.exe
rem 用法：build.cmd   或在外部先 set GODOT=... 指定引擎路径

set "PROJ=%~dp0"
if "%GODOT%"=="" set "GODOT=D:\godex\Godot_v4.7.2-stable_win64_console.exe"

if not exist "%GODOT%" (
    echo [ERR] 找不到 Godot: %GODOT%
    echo       先 set GODOT=完整路径\Godot_v4.7.2-stable_win64_console.exe
    exit /b 1
)

rem 版本取最近的 git tag，取不到就用 v0.0.0
set "TAG="
for /f "delims=" %%i in ('git describe --tags --abbrev=0 2^>nul') do set "TAG=%%i"
if "%TAG%"=="" set "TAG=v0.0.0"

if not exist "%PROJ%build" mkdir "%PROJ%build"

set "OUT=build\poker-pusher-%TAG%-windows-x86_64.exe"
if exist "%PROJ%%OUT%" del /q "%PROJ%%OUT%"

echo [..] 导出 %OUT%
"%GODOT%" --headless --path "%PROJ%." --export-release "Windows Desktop" "%OUT%"
if errorlevel 1 (
    echo [ERR] 导出失败
    exit /b 1
)

echo [OK] %PROJ%%OUT%
