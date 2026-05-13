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
; Installer output — CI sets the actual output path via /O flag
OutputBaseFilename=pp-gui-setup
SetupIconFile=..\..\assets\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
; Allow installing without admin (installs to user AppData in that case)
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
; Include all files from the Flutter Windows release bundle.
; CI places them into installer\windows\bundle\ before running Inno Setup.
Source: "bundle\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
function VCVersionInstalled(const ProductCode: string): Boolean;
begin
  Result := RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + ProductCode) or
            RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + ProductCode);
end;

function InitializeSetup(): Boolean;
var
  VC2015to2022x64: string;
  ErrorCode: Integer;
begin
  Result := True;
  VC2015to2022x64 := '{14C61D60-1729-4AD0-A442-263D7E7D906E}'; // Microsoft Visual C++ 2015-2022 Redistributable (x64)
  
  if not VCVersionInstalled(VC2015to2022x64) then
  begin
    if MsgBox('Для работы приложения требуется Microsoft Visual C++ 2015-2022 Redistributable. Установить его сейчас?', mbConfirmation, MB_YESNO) = idYes then
    begin
      // Note: In a real CI environment, you'd download the installer or include it.
      // For now, we'll just open the download page.
      if not ShellExec('open', 'https://aka.ms/vs/17/release/vc_redist.x64.exe', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode) then
      begin
        MsgBox('Не удалось открыть ссылку для скачивания. Пожалуйста, установите Visual C++ Redistributable вручную.', mbError, MB_OK);
      end;
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
