!ifndef VERSION
!define VERSION "0.1.0"
!endif

!ifndef OUTFILE
!define OUTFILE "dist\installers\OmniLux-Setup.exe"
!endif

Name "OmniLux"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\OmniLux"
RequestExecutionLevel user
Unicode true

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "OmniLux"
VIAddVersionKey "CompanyName" "OmniLux"
VIAddVersionKey "LegalCopyright" "Copyright OmniLux"
VIAddVersionKey "FileDescription" "OmniLux Windows Installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File "install-omnilux.ps1"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\OmniLux"
  CreateShortcut "$SMPROGRAMS\OmniLux\Open OmniLux.lnk" "http://localhost:4000"
  CreateShortcut "$SMPROGRAMS\OmniLux\Uninstall OmniLux.lnk" "$INSTDIR\Uninstall.exe"
  ExecWait 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\install-omnilux.ps1"'
SectionEnd

Section "Uninstall"
  ExecWait 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "docker compose --env-file $$env:LOCALAPPDATA\OmniLux\.env -f $$env:LOCALAPPDATA\OmniLux\docker-compose.yml down"'
  Delete "$SMPROGRAMS\OmniLux\Open OmniLux.lnk"
  Delete "$SMPROGRAMS\OmniLux\Uninstall OmniLux.lnk"
  RMDir "$SMPROGRAMS\OmniLux"
  Delete "$INSTDIR\install-omnilux.ps1"
  Delete "$INSTDIR\Uninstall.exe"
SectionEnd
