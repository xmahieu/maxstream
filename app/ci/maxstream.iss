; Inno Setup script for the Windows installer (built by GitHub Actions)
#define AppVersion GetEnv("APP_VERSION")

[Setup]
AppId={{7E3C1D52-8B0A-4C55-9C1E-6A2B7F0D4E11}
AppName=MaxStream
AppVersion={#AppVersion}
AppPublisher=MaxStreamKodi
AppPublisherURL=https://maxstreamkodi-cyber.github.io/maxstream/
DefaultDirName={autopf}\MaxStream
DefaultGroupName=MaxStream
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=MaxStream-Setup
SetupIconFile=windows\app_icon.ico
UninstallDisplayIcon={app}\maxstream.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MaxStream"; Filename: "{app}\maxstream.exe"
Name: "{autodesktop}\MaxStream"; Filename: "{app}\maxstream.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\maxstream.exe"; Description: "{cm:LaunchProgram,MaxStream}"; Flags: nowait postinstall skipifsilent
