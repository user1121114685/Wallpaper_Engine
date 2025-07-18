call flutter build windows
del %~dp0wallpaper_engine_workshop_downloader.zip
%~dp07z.exe a -r %~dp0wallpaper_engine_workshop_downloader.zip %~dp0build\windows\x64\runner\Release\*
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" .\build.iss