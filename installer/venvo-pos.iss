; Venvo POS — Windows installer
;
; Built with Inno Setup 6 (https://jrsoftware.org/isinfo.php), which is the
; least ceremonious way to ship a Flutter desktop application on Windows: one
; .exe, no runtime to install, no store account, and an uninstaller that
; Windows' own "Apps & features" list knows about.
;
; To produce an installer:
;
;   1. flutter build windows --release
;   2. iscc installer\venvo-pos.iss
;
; The output lands in installer\output\. Step 1 needs the Visual Studio
; Build Tools with the "Desktop development with C++" workload; see the
; README.
;
; Last compiled 14 Nov 2026 against Inno Setup 6.5.6 and a release build made
; with Flutter 3.47.9: a 14.4 MB setup .exe, verified by installing it
; silently to a scratch directory, launching the installed binary, and
; uninstalling it again. It has NOT yet been run on a clean machine — one
; without the Visual Studio redistributables and the Flutter SDK — which is
; the remaining check before handover.
;
; What it deliberately does NOT do:
;
;   * It does not touch the data directory. Business data lives under
;     %APPDATA%\lk.venvoglobal\VenvoPOS and is left alone by both install and
;     uninstall, so upgrading never risks the database and removing the
;     program never destroys the business's records. The uninstaller says so.
;   * It does not install per-machine by default. A per-user install needs no
;     administrator rights, which matters in a shop where the person using
;     the till is not an administrator.

#define AppName "Venvo POS"
#define AppPublisher "Venvo Global (Pvt) Ltd"
#define AppVersion "0.1.0"
#define AppExeName "venvo_pos.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; A stable GUID: Windows matches an upgrade to an existing install by it, so
; it must never change between releases of this product.
AppId={{8C4E1A96-7F4D-4B23-9E55-2C0B6D7A1F38}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}

; Per-user by default: no administrator prompt, which is what a shop counter
; needs. Pass /ALLUSERS at the command line for a machine-wide install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

OutputDir=output
OutputBaseFilename=venvo-pos-{#AppVersion}-setup
; The runner's own icon, which is the one Windows already shows for the
; executable, so the installer and the program match.
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; 64-bit only. Flutter desktop on Windows does not build for x86.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Shown on the "ready to install" page, so whoever runs it knows what will
; and will not be touched.
InfoBeforeFile=install-notes.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a shortcut on the desktop"; \
  GroupDescription: "Shortcuts:"

[Files]
; The whole release bundle. A Flutter application needs its DLLs and its
; data\ folder beside the executable, so this is a recursive copy rather than
; a list of files.
Source: "{#BuildDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*"; DestDir: "{app}\data"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
  Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
  Description: "Open {#AppName} now"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Only what the installer put there. The data directory is not listed on
; purpose: uninstalling the program must not destroy the business's records.
Type: filesandordirs; Name: "{app}\data"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // SuppressibleMsgBox, not MsgBox, and not at all when uninstalling
  // silently. A plain MsgBox is shown even under /VERYSILENT
  // /SUPPRESSMSGBOXES, where there is nobody to click OK, so the uninstaller
  // waits for a human for ever. That hangs an unattended uninstall — which is
  // what an IT department does, and what an installer that removes an old
  // version before fitting a new one does.
  if (CurUninstallStep = usPostUninstall) and (not UninstallSilent) then
    SuppressibleMsgBox(
      'Venvo POS has been removed.' + #13#10#13#10 +
      'Your business data has been left where it is, under:' + #13#10 +
      ExpandConstant('{userappdata}') + '\lk.venvoglobal\VenvoPOS' + #13#10 + #13#10 +
      'That folder holds the database, the attachments, your backups and ' +
      'your exports. Delete it by hand only if you are certain you will ' +
      'never need the records again — and take a copy somewhere else first.',
      mbInformation, MB_OK, IDOK);
end;
