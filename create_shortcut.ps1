$wshell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcut = $wshell.CreateShortcut("$desktop\Moodiary.lnk")
$shortcut.TargetPath = 'D:\moodiary\build\windows\x64\runner\Release\mood_diary.exe'
$shortcut.WorkingDirectory = 'D:\moodiary\build\windows\x64\runner\Release'
$shortcut.Save()
Write-Host "Created at: $desktop\Moodiary.lnk"
