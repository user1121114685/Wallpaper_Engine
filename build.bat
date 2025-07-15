call flutter build windows
del %~dp0wallpaper_engine_workshop_downloader.zip
%~dp07z.exe a -r %~dp0wallpaper_engine_workshop_downloader.zip %~dp0build\windows\x64\runner\Release\*
%~dp07z.exe x %~dp0wallpaper_engine_workshop_downloader.zip -ax!steamcmd.exe -aoa -o%~dp0wallpaper_engine_workshop_downloader