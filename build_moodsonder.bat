@echo off
chcp 65001 >nul
cd /d D:\moodsonder

echo ============================================
echo  Moodsonder Builder - 从 Moodiary 构建 Moodsonder
echo ============================================
echo.

:: 备份原始文件
echo [1/5] 备份原始构建配置...
copy /Y windows\CMakeLists.txt windows\CMakeLists.txt.moodiary.bak >nul
copy /Y windows\runner\main.cpp windows\runner\main.cpp.moodiary.bak >nul
copy /Y windows\runner\Runner.rc windows\runner\Runner.rc.moodiary.bak >nul
copy /Y lib\l10n\app_localizations_zh.dart lib\l10n\app_localizations_zh.dart.moodiary.bak >nul
copy /Y lib\l10n\app_localizations_en.dart lib\l10n\app_localizations_en.dart.moodiary.bak >nul
copy /Y lib\l10n\intl_zh.arb lib\l10n\intl_zh.arb.moodiary.bak >nul
copy /Y lib\l10n\intl_en.arb lib\l10n\intl_en.arb.moodiary.bak >nul
echo   ✓ 备份完成

:: 修改 BINARY_NAME -> moodsonder
echo [2/5] 修改构建配置为 Moodsonder...
powershell -Command "(gc windows\CMakeLists.txt) -replace 'set\(BINARY_NAME \"mood_diary\"\)', 'set(BINARY_NAME \"moodsonder\")' | Set-Content windows\CMakeLists.txt"

:: 修改窗口标题
powershell -Command "(gc windows\runner\main.cpp) -replace 'Create\(\"Moodiary\"', 'Create(\"Moodsonder\"' | Set-Content windows\runner\main.cpp"

:: 修改 Runner.rc（保留 CompanyName 和 ProductName 不变——共享数据用）
powershell -Command "(gc windows\runner\Runner.rc) -replace 'VALUE \"FileDescription\", \"moodiary\"', 'VALUE \"FileDescription\", \"Moodsonder\"' | Set-Content windows\runner\Runner.rc"
powershell -Command "(gc windows\runner\Runner.rc) -replace 'VALUE \"InternalName\", \"moodiary\"', 'VALUE \"InternalName\", \"moodsonder\"' | Set-Content windows\runner\Runner.rc"
powershell -Command "(gc windows\runner\Runner.rc) -replace 'VALUE \"OriginalFilename\", \"moodiary.exe\"', 'VALUE \"OriginalFilename\", \"moodsonder.exe\"' | Set-Content windows\runner\Runner.rc"
powershell -Command "(gc windows\runner\Runner.rc) -replace 'Copyright \(C\) 2024 Moodiary', 'Copyright (C) 2024 Moodsonder' | Set-Content windows\runner\Runner.rc"

:: 修改本地化文件
powershell -Command "(gc lib\l10n\app_localizations_zh.dart) -replace \"appName => 'Moodiary'\", \"appName => 'Moodsonder'\" | Set-Content lib\l10n\app_localizations_zh.dart"
powershell -Command "(gc lib\l10n\app_localizations_zh.dart) -replace \"startTitle2 => 'Moodiary'\", \"startTitle2 => 'Moodsonder'\" | Set-Content lib\l10n\app_localizations_zh.dart"
powershell -Command "(gc lib\l10n\app_localizations_en.dart) -replace \"appName => 'Moodiary'\", \"appName => 'Moodsonder'\" | Set-Content lib\l10n\app_localizations_en.dart"
powershell -Command "(gc lib\l10n\intl_zh.arb) -replace '\"appName\": \"Moodiary\"', '\"appName\": \"Moodsonder\"' | Set-Content lib\l10n\intl_zh.arb"
powershell -Command "(gc lib\l10n\intl_zh.arb) -replace '\"startTitle2\": \"Moodiary\"', '\"startTitle2\": \"Moodsonder\"' | Set-Content lib\l10n\intl_zh.arb"
powershell -Command "(gc lib\l10n\intl_en.arb) -replace '\"appName\": \"Moodiary\"', '\"appName\": \"Moodsonder\"' | Set-Content lib\l10n\intl_en.arb"
echo   ✓ 配置修改完成

:: 清理旧的构建缓存
echo [3/5] 清理旧的构建缓存...
if exist build\windows rmdir /s /q build\windows
echo   ✓ 缓存清理完成

:: 构建
echo [4/5] 开始编译 Moodsonder Windows 版...
echo   （这可能耗时 5-10 分钟，请耐心等待）
echo.
C:\tools\flutter\bin\flutter.bat build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   ❌ 构建失败！正在恢复文件...
    goto :restore
)
echo   ✓ 构建成功！

:: 恢复原始文件
:restore
echo [5/5] 恢复原始构建配置...
copy /Y windows\CMakeLists.txt.moodiary.bak windows\CMakeLists.txt >nul
copy /Y windows\runner\main.cpp.moodiary.bak windows\runner\main.cpp >nul
copy /Y windows\runner\Runner.rc.moodiary.bak windows\runner\Runner.rc >nul
copy /Y lib\l10n\app_localizations_zh.dart.moodiary.bak lib\l10n\app_localizations_zh.dart >nul
copy /Y lib\l10n\app_localizations_en.dart.moodiary.bak lib\l10n\app_localizations_en.dart >nul
copy /Y lib\l10n\intl_zh.arb.moodiary.bak lib\l10n\intl_zh.arb >nul
copy /Y lib\l10n\intl_en.arb.moodiary.bak lib\l10n\intl_en.arb >nul

:: 清理备份文件
del windows\CMakeLists.txt.moodiary.bak >nul 2>&1
del windows\runner\main.cpp.moodiary.bak >nul 2>&1
del windows\runner\Runner.rc.moodiary.bak >nul 2>&1
del lib\l10n\*.moodiary.bak >nul 2>&1

echo   ✓ 文件恢复完成
echo.
echo ============================================
if exist build\windows\x64\runner\Release\moodsonder.exe (
    echo  ✅ 构建完成！
    echo  输出: build\windows\x64\runner\Release\moodsonder.exe
    echo.
    echo  快捷方式已为你创建在 D:\桌面\Moodsonder.lnk
    echo  数据目录与 Moodiary 共享: %%APPDATA%%\cn.yooss\moodiary
) else (
    echo  ❌ 构建失败，请检查上面的错误信息
)
echo ============================================
pause
