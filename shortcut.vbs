Set ws = WScript.CreateObject("WScript.Shell")
Set sc = ws.CreateShortcut(ws.SpecialFolders("Desktop") & "\Moodiary.lnk")
sc.TargetPath = "D:\moodiary\build\windows\x64\runner\Release\mood_diary.exe"
sc.WorkingDirectory = "D:\moodiary\build\windows\x64\runner\Release"
sc.Description = "Moodiary - open source diary app"
sc.Save()
