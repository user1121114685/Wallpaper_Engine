del %~dp0\wallpaper_engine_workshop_downloader.zip
REM a 添加文件 -r 表示递归
%~dp07z.exe a -r %~dp0\wallpaper_engine_workshop_downloader.zip %~dp0build\windows\runner\Release\*
REM x 表示解压 -ax 表示跳过 -aoa 表示覆盖 -o 解压目录
%~dp07z.exe x %~dp0\wallpaper_engine_workshop_downloader.zip -ax!steamcmd.exe -aoa -o%~dp0\wallpaper_engine_workshop_downloader