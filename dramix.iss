; Inno Setup script for the Dramix Windows client.
;
; Build:  ISCC.exe dramix.iss   ->  dist_windows\Dramix-setup-<ver>-x64.exe
; Requires the release build to exist first:
;   flutter build windows --release   (see tools/build_windows.ps1)

#define MyAppName "Dramix"
#define MyAppVersion "1.0.0"
#define MyAppExeName "dramix.exe"
#define MyAppPublisher "Dramix"

[Setup]
; A stable, unique AppId keeps upgrades in place instead of installing twice.
AppId={{7F3B9C41-5D2E-4A86-9E10-8B4C1D6A2F93}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=windows\runner\resources\app_icon.ico
OutputDir=dist_windows
OutputBaseFilename=Dramix-setup-{#MyAppVersion}-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
MinVersion=10.0

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter release bundle: exe, DLLs and the data\ folder.
; WebView2 writes its profile next to the executable at runtime — never ship it.
Source: "build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; \
    Excludes: "dramix.exe.WebView2\*,*.log"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; \
    Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; \
    Flags: nowait postinstall skipifsilent
