; PP GUI — Inno Setup installer script
; Installs to Program Files, creates desktop + Start Menu shortcuts,
; and registers the application in Add/Remove Programs.

#define MyAppName "PP GUI"
#define MyAppPublisher "vakaka1"
#define MyAppURL "https://github.com/vakaka1/pp-gui"
#define MyAppExeName "pp_gui.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\PP GUI
DefaultGroupName={#MyAppName}
AllowNoIcons=no
OutputBaseFilename=pp-gui-setup
SetupIconFile=..\..\assets\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoProductName={#MyAppName}
VersionInfoDescription=PP Protocol GUI Client

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "bundle\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]

function IsFileInstalled(const FileName: string): Boolean;
begin
  Result := FileExists(ExpandConstant('{sys}\' + FileName));
end;

function IsVcRuntimeDllInstalled(): Boolean;
begin
  Result := IsFileInstalled('vcruntime140.dll') and
            IsFileInstalled('msvcp140.dll');
end;

function VCVersionInstalled(const ProductCode: string): Boolean;
begin
  Result := RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + ProductCode) or
            RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + ProductCode) or
            RegKeyExists(HKEY_CURRENT_USER, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + ProductCode);
end;

function IsVCRegistryInstalled(): Boolean;
var
  I: Integer;
  ProductCodes: array[0..9] of string;
begin
  Result := False;
  ProductCodes[0] := '{14C61D60-1729-4AD0-A442-263D7E7D906E}';
  ProductCodes[1] := '{5C000F44-44C2-4387-9D2C-A169B8E0C46F}';
  ProductCodes[2] := '{804879EE-A175-4152-9E79-A9714634F97A}';
  ProductCodes[3] := '{A49F249F-0C91-497F-86DF-B2585E8E76B7}';
  ProductCodes[4] := '{B58E4A3A-F77D-4A5B-B6F3-AB05C631511F}';
  ProductCodes[5] := '{C0048689-E88F-4F35-930D-D2F3D8A1C3B6}';
  ProductCodes[6] := '{FFE6602D-3CCD-4B0D-83C1-2F6259FF19E1}';
  ProductCodes[7] := '{3BDA6E09-1A0C-4B3B-8C5B-1A0F3E0A5B6C}';
  ProductCodes[8] := '{3DA8C819-268E-4A4A-8A8A-0A0F0A0B0C0D}';
  ProductCodes[9] := '{E31CB1A4-76B5-4CB5-8B5B-3A5E0A1B2C3D}';
  for I := 0 to High(ProductCodes) do
  begin
    if VCVersionInstalled(ProductCodes[I]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function IsVCRedistInstalled(): Boolean;
begin
  if IsVcRuntimeDllInstalled() then
  begin
    Result := True;
    Exit;
  end;
  Result := IsVCRegistryInstalled();
end;

function InitializeSetup(): Boolean;
var
  ErrorCode: Integer;
  Answer: Integer;
begin
  Result := True;
  if not IsVCRedistInstalled() then
  begin
    Answer := MsgBox('Для работы приложения требуется Microsoft Visual C++ 2015-2022 Redistributable (x64).'#13#10#13#10'Установить его сейчас? (Нажмите "Нет", чтобы продолжить установку без него)', mbConfirmation, MB_YESNOCANCEL);
    if Answer = idYes then
    begin
      if not ShellExec('open', 'https://aka.ms/vs/17/release/vc_redist.x64.exe', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode) then
      begin
        MsgBox('Не удалось открыть ссылку для скачивания. Пожалуйста, установите Visual C++ Redistributable вручную.', mbError, MB_OK);
      end;
      Result := True;
    end
    else if Answer = idCancel then
    begin
      Result := False;
    end;
  end;
end;

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
