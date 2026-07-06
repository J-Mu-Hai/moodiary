@echo off
chcp 65001 >nul
cd /d D:\moodsonder

echo ============================================
echo  Moodiary Builder - 构建原版 Moodiary
echo ============================================
echo.

:: 清理旧的构建缓存
echo [1/3] 清理旧的构建缓存...
if exist build\windows rmdir /s /q build\windows
echo   ✓ 缓存清理完成

:: 构建
echo [2/3] 开始编译 Moodiary Windows 版...
echo   （这可能耗时 5-10 分钟，请耐心等待）
echo.
C:\tools\flutter\bin\flutter.bat build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo   ❌ 构建失败！
    pause
    exit /b 1
)
echo   ✓ 构建成功！

:: 创建/更新快捷方式
echo [3/3] 更新快捷方式...
powershell -Command "
    \$wshell = New-Object -ComObject WScript.Shell
    \$lnk = \$wshell.CreateShortcut('D:\桌面\Moodiary.lnk')
    \$lnk.TargetPath = 'D:\moodsonder\build\windows\x64\runner\Release\mood_diary.exe'
    \$lnk.WorkingDirectory = 'D:\moodsonder\build\windows\x64\runner\Release'
    \$lnk.Save()
    Write-Host '  ✓ 快捷方式已更新'
"
echo.
echo ============================================
echo  ✅ 构建完成！
echo  输出: build\windows\x64\runner\Release\mood_diary.exe
echo  快捷方式: D:\桌面\Moodiary.lnk
echo ============================================
pause
