[Setup]
AppName=Deck Master
AppVersion=1.2.0
AppPublisher=Giuseppe
AppPublisherURL=
AppSupportURL=
DefaultDirName={autopf}\Deck Master
DefaultGroupName=Deck Master
OutputDir=..\installer_output
OutputBaseFilename=DeckMaster_Setup_1.2.0
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\deck_master.exe
UninstallDisplayName=Deck Master
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
LicenseFile=
; Mostra schermata di benvenuto
WizardImageFile=compiler:WizClassicImage.bmp
WizardSmallImageFile=compiler:WizClassicSmallImage.bmp

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Crea icona sul Desktop"; GroupDescription: "Icone aggiuntive:"; Flags: unchecked

[Files]
; Eseguibile principale
Source: "..\build\windows\x64\runner\Release\deck_master.exe"; DestDir: "{app}"; Flags: ignoreversion

; Tutte le DLL e i file nella cartella Release
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

; Cartella data (Flutter assets, icone, font, ecc.)
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Deck Master"; Filename: "{app}\deck_master.exe"; IconFilename: "{app}\deck_master.exe"
Name: "{autodesktop}\Deck Master"; Filename: "{app}\deck_master.exe"; IconFilename: "{app}\deck_master.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\deck_master.exe"; Description: "Avvia Deck Master"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
