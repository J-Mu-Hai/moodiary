@echo off
call "D:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
set PATH=C:\tools\flutter\bin;C:\tools;%PATH%
set LIB=%LIB%;D:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\atlmfc\lib\x64
cd /d D:\moodiary
flutter build windows --verbose
exit /b %ERRORLEVEL%
