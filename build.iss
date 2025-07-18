; 这是由 Inno Setup 脚本向导生成的脚本。
; 有关创建 Inno Setup 脚本文件的详细信息请查阅帮助文档

#define MyAppName "Wallpaper Engine 壁纸下载器"
#define MyAppVersion "0.2.7"
#define MyAppPublisher "联盟少侠"
#define MyIconFileName ".\windows\runner\resources\app_icon.ico"

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Setup]
; 注: AppId的值为唯一标识此应用程序。
; 不要为其他安装程序使用相同的AppId值。
AppId={{e2bcafae-1d28-4d94-8dad-f18a4198a487}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={code:GetDefaultInstallDir}
DefaultGroupName={#MyAppName}
OutputBaseFilename=Wallpaper_Engine
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile={#MyIconFileName}
; 请求管理员权限
PrivilegesRequired=admin

[Files]
; 将当前目录下 \build\windows\x64\runner\Release\* 中的所有文件打包
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\wallpaper_engine_workshop_downloader.exe"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\wallpaper_engine_workshop_downloader.exe"

[Run]
; 移除安装后自动运行，避免权限问题
; Filename: "{app}\wallpaper_engine_workshop_downloader.exe"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
// 检查路径是否包含空格或非ASCII字符（可能是中文等）
function PathContainsInvalidChars(const Path: String): Boolean;
var
  i: Integer;
begin
  // 检查是否包含空格
  if Pos(' ', Path) > 0 then
  begin
    Result := True;
    Exit;
  end;

  // 检查是否包含非ASCII字符（大于127的字符，可能是中文等）
  for i := 1 to Length(Path) do
  begin
    if Ord(Path[i]) > 127 then
    begin
      Result := True;
      Exit;
    end;
  end;

  // 如果没有空格也没有非ASCII字符，则路径是合法
  Result := False;
end;

// 在初始化安装时检查并关闭正在运行的程序
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // 先尝试关闭正在运行的程序
  Exec('taskkill.exe', '/F /IM wallpaper_engine_workshop_downloader.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // 不管是否成功关闭，都继续进行，如果失败，可能程序没运行

  // 继续安装
  Result := True;
end;

// 在用户点击下一步时检查路径
function NextButtonClick(CurPageID: Integer): Boolean;
var
  SelectedPath: String;
begin
  // 如果是在安装目录页面
  if CurPageID = wpSelectDir then
  begin
    // 获取用户当前选择的安装路径
    SelectedPath := WizardDirValue();

    // 检查路径是否包含非法字符（空格或中文等）
    if PathContainsInvalidChars(SelectedPath) then
    begin
      MsgBox('错误：安装路径中不能包含空格或中文字符。' + #13#10 + '当前路径: ' + SelectedPath, mbError, MB_OK);
      Result := False; // 阻止继续
      Exit;
    end;
  end;

  // 路径合法，继续安装
  Result := True;
end;

function GetDefaultInstallDir(Param: String): String;
var
  Drive: String;
begin
  // 先尝试使用 D: 盘
  Drive := 'D:\';
  if DirExists(Drive) then
  begin
    // D: 盘存在，可以使用
    Result := Drive + 'wallpaper_engine_workshop_downloader';
  end
  else
  begin
    // D: 不存在或不是固定盘，使用默认的 {autoprograms}
    Result := ExpandConstant('{autoprograms}\wallpaper_engine_workshop_downloader');
  end;
end;