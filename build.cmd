@echo off
setlocal

rem 导出 Windows 单文件 exe（PCK 内嵌）。需要 Godot 4.7.2 导出模板。
rem 用法：build.cmd        或在外部先 set GODOT=... 指定引擎路径

set "PROJ=%~dp0"
if "%GODOT%"=="" set "GODOT=D:\godex\Godot_v4.7.2-stable_win64_console.exe"

if not exist "%GODOT%" (
    echo [ERR] 找不到 Godot: %GODOT%
    echo       先 set GODOT=完整路径\Godot_v4.7.2-stable_win64_console.exe
    exit /b 1
)

if not exist "%PROJ%build" mkdir "%PROJ%build"

"%GODOT%" --headless --path "%PROJ%." --export-release "Windows Desktop" "build\poker-pusher.exe"
if errorlevel 1 (
    echo [ERR] 导出失败
    exit /b 1
)

echo [OK] %PROJ%build\poker-pusher.exe
