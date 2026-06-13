@echo off
setlocal enabledelayedexpansion

call "D:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
set PATH=C:\tools\flutter\bin;C:\tools;%PATH%
set LIB=%LIB%;D:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\atlmfc\lib\x64

cd /d D:\moodiary

:: 生成版本号（按当前时间）
set timestamp=%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set timestamp=%timestamp: =0%
set output_dir=build\release\moodiary_%timestamp%

flutter build windows --verbose

:: 如果构建成功，复制一份到版本目录
if %ERRORLEVEL% equ 0 (
    echo.
    echo ========================================
    echo 构建成功！备份到: %output_dir%
    echo ========================================
    xcopy /E /I /Y build\windows\x64\runner\Release %output_dir% >nul
) else (
    echo 构建失败，请查看上方错误信息
)

exit /b %ERRORLEVEL%
