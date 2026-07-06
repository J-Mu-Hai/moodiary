$wshell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')

# 创建 Moodiary 快捷方式
$oldExe = 'D:\moodsonder\build\windows\x64\runner\Release\mood_diary.exe'
if (Test-Path $oldExe) {
    $lnk1 = $wshell.CreateShortcut("$desktop\Moodiary.lnk")
    $lnk1.TargetPath = $oldExe
    $lnk1.WorkingDirectory = [System.IO.Path]::GetDirectoryName($oldExe)
    $lnk1.Save()
    Write-Host "✅ Moodiary.lnk -> $desktop"
} else {
    Write-Host "⚠️ mood_diary.exe not found at: $oldExe"
}

# 创建 Moodsonder 快捷方式
$newExe = 'D:\moodsonder\build\windows\x64\runner\Release\moodsonder.exe'
if (Test-Path $newExe) {
    $lnk2 = $wshell.CreateShortcut("$desktop\Moodsonder.lnk")
    $lnk2.TargetPath = $newExe
    $lnk2.WorkingDirectory = [System.IO.Path]::GetDirectoryName($newExe)
    $lnk2.Save()
    Write-Host "✅ Moodsonder.lnk -> $desktop"
} else {
    Write-Host "⚠️ moodsonder.exe not found at: $newExe"
}

Write-Host ""
Write-Host "两个版本共享同一份数据目录:"
Write-Host "  %APPDATA%\cn.yooss\moodiary\"
Write-Host "  即: $env:APPDATA\cn.yooss\moodiary"
