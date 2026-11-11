#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceRoot
  #define SourceRoot ".."
#endif
#ifndef BuildRoot
  #define BuildRoot "..\build"
#endif
[Setup]
AppId={{F1FA958A-B84D-4FAD-A658-9B58690FD93D}
AppName=iCUE Memory Guard
AppVersion={#AppVersion}
AppVerName=iCUE Memory Guard {#AppVersion} (Experimental)
AppPublisher=JZB Apps
AppPublisherURL=https://jzbapps.com
AppSupportURL=mailto:support@jzbapps.com
AppUpdatesURL=https://github.com/jb14813/iCUE-Memory-Guard/releases
VersionInfoDescription=JZB Apps iCUE Memory Guard (Experimental) Setup
VersionInfoProductName=iCUE Memory Guard
VersionInfoVersion={#AppVersion}.0
VersionInfoProductVersion={#AppVersion}
DefaultDirName={autopf}\JZB Apps\iCUE Memory Guard
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
OutputDir={#BuildRoot}
OutputBaseFilename=iCUEMemoryGuard-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#SourceRoot}\branding\jzb-apps.ico
WizardImageFile={#SourceRoot}\branding\wizard-large.png
WizardSmallImageFile={#SourceRoot}\branding\wizard-small.png
DisableWelcomePage=no
LicenseFile={#SourceRoot}\LICENSE
InfoBeforeFile={#SourceRoot}\installer\SetupNotes.txt
SetupLogging=yes
AlwaysRestart=no
RestartIfNeededByRun=no
CloseApplications=no
RestartApplications=no
#ifdef SelfSign
SignTool=JzbOwn
SignedUninstaller=yes
#else
SignedUninstaller=no
#endif
UninstallDisplayName=iCUE Memory Guard (Experimental)
UninstallDisplayIcon={uninstallexe}
[Messages]
WelcomeLabel2=Apply the experimental memory fix for the exact tested iCUE CPU-ID service and SDK. Review compatibility and recovery notes before continuing.
InfoBeforeLabel=Compatibility and risks
InfoBeforeClickLabel=
[Files]
Source: "{#SourceRoot}\Manage-iCUEMemoryGuard.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\src\*"; DestDir: "{app}\src"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\patches\*.json"; DestDir: "{app}\patches"; Flags: ignoreversion
Source: "{#SourceRoot}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\VALIDATION.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\SIGNING.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\SECURITY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\VERSION"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\Manage-iCUEMemoryGuard.ps1"; DestDir: "{tmp}\icue-check"; Flags: dontcopy
Source: "{#SourceRoot}\src\*"; DestDir: "{tmp}\icue-check\src"; Flags: dontcopy recursesubdirs createallsubdirs
Source: "{#SourceRoot}\patches\*.json"; DestDir: "{tmp}\icue-check\patches"; Flags: dontcopy
[Icons]
Name: "{commonprograms}\iCUE Memory Guard\Instructions"; Filename: "{app}\README.md"
Name: "{commonprograms}\iCUE Memory Guard\Restore and uninstall"; Filename: "{uninstallexe}"
Name: "{commonprograms}\iCUE Memory Guard\JZB Apps website"; Filename: "https://jzbapps.com"
Name: "{commonprograms}\iCUE Memory Guard\Email support"; Filename: "mailto:support@jzbapps.com"
[Code]
var
  ConfigurationSucceeded: Boolean;
  FailureText: String;
  ContactLinks: TNewLinkLabel;
function RunGuard(Action, Root: String): Boolean;
var
  ExitCode: Integer;
  Args: String;
begin
  ExitCode := -1;
  Args := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + Root + '\Manage-iCUEMemoryGuard.ps1" -Action ' + Action + ' -Quiet';
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Args, Root, SW_HIDE, ewWaitUntilTerminated, ExitCode);
  if Result then Result := ExitCode = 0;
  Log(Format('Manager action %s exit code: %d', [Action, ExitCode]));
end;
procedure ContactLinkClick(Sender: TObject; const Link: string; LinkType: TSysLinkType);
var
  ErrorCode: Integer;
begin
  if (LinkType = sltURL) and ((Link = 'https://jzbapps.com') or (Link = 'mailto:support@jzbapps.com')) then
    ShellExecAsOriginalUser('open', Link, '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;
procedure InitializeWizard;
begin
  ConfigurationSucceeded := False;
  ContactLinks := TNewLinkLabel.Create(WizardForm);
  ContactLinks.Parent := WizardForm;
  ContactLinks.Left := ScaleX(12);
  ContactLinks.Top := WizardForm.CancelButton.Top + ScaleY(4);
  ContactLinks.Width := ScaleX(260);
  ContactLinks.Height := ScaleY(20);
  ContactLinks.Caption := '<a href="https://jzbapps.com">jzbapps.com</a>  |  <a href="mailto:support@jzbapps.com">Email support</a>';
  ContactLinks.OnLinkClick := @ContactLinkClick;
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if CompareText(WizardDirValue, ExpandConstant('{autopf}\JZB Apps\iCUE Memory Guard')) <> 0 then begin
    Result := 'Use the protected default Program Files location.';
    Exit;
  end;
  ExtractTemporaryFiles('{tmp}\icue-check\*');
  if not RunGuard('Check', ExpandConstant('{tmp}\icue-check')) then
    Result := 'Compatibility or recovery checks failed. Only the exact tested service 5.52.93.0 and SDK 1.3.4.7 are supported. Setup made no patch changes. Run the manager Check action for details.';
end;
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    WizardForm.StatusLabel.Caption := 'Applying the tested memory fix...';
    ConfigurationSucceeded := RunGuard('Install', ExpandConstant('{app}'));
    if not ConfigurationSucceeded then begin
      FailureText := 'The memory fix could not be applied safely. Setup failed. The recovery manager, uninstaller and backups were retained. Run the installed manager Status action and resolve the reported conflict before retrying Setup or uninstall.';
      Log(FailureText);
      SuppressibleMsgBox(FailureText, mbError, MB_OK, IDOK);
    end;
  end;
end;
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if ConfigurationSucceeded then
      WizardForm.FinishedLabel.Caption := 'iCUE Memory Guard is installed and the tested memory fix is active.'
    else begin
      WizardForm.FinishedHeadingLabel.Caption := 'Setup failed';
      WizardForm.FinishedLabel.Caption := FailureText;
    end;
  end;
end;
function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if not ConfigurationSucceeded then Result := 10;
end;
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    if not RunGuard('Uninstall', ExpandConstant('{app}')) then begin
      SuppressibleMsgBox('Restoration failed. Recovery files, backups and the uninstaller were retained. Run the manager Status action, resolve the conflict, and retry uninstall.', mbError, MB_OK, IDOK);
      Abort;
    end;
  end;
end;
