# BauSpur - Entwicklungsumgebung einrichten (Windows)
#
# Installiert, falls noch nicht vorhanden:
#   1. Git fuer Windows                     (winget)
#   2. Visual Studio 2022 Community         (winget) mit "Desktopentwicklung mit C++"
#   3. VS Code                              (winget, optional - zum Ansehen/Bearbeiten des Codes)
#   4. Flutter SDK                          (git clone nach %USERPROFILE%\dev\flutter, in den Benutzer-PATH)
# Danach: BauSpur-Projekt einrichten, Tests ausfuehren, lokales Git-Repository anlegen.
#
# Das Skript laeuft als normaler Benutzer. Die Installer von Git und Visual Studio fragen
# selbst per Windows-Dialog nach Adminrechten - dort mit "Ja" bestaetigen.
# Es kann beliebig oft erneut gestartet werden (bereits Installiertes wird uebersprungen).
#
# Umzug auf einen neuen PC: BauSpur-Ordner kopieren (oder klonen) und dieses Skript dort starten.
# Die Flutter-Version steht in tools\flutter-version.txt und wird auf dem neuen PC genau so installiert.

param(
    [string]$FlutterDir = (Join-Path $env:USERPROFILE 'dev\flutter'),
    [switch]$OhneVSCode
)

$ErrorActionPreference = 'Continue'
$tools = $PSScriptRoot
$projekt = Split-Path $tools -Parent
$log = Join-Path $tools 'install.log'
Start-Transcript -Path $log -Append | Out-Null

function Schritt($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Ok($text) { Write-Host "  OK: $text" -ForegroundColor Green }
function Abbruch($text) {
    Write-Host "`nFEHLER: $text" -ForegroundColor Red
    Write-Host "Protokoll: $log"
    Stop-Transcript | Out-Null
    Read-Host 'Enter zum Schliessen'
    exit 1
}
function PfadNeuLaden {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}
function WingetInstall($id, $extra) {
    $parameter = @('install', '--id', $id, '-e', '--source', 'winget',
                   '--accept-package-agreements', '--accept-source-agreements') + $extra
    & winget @parameter
    return $LASTEXITCODE
}

# ---------------------------------------------------------------- winget
Schritt 'Paketmanager winget'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Abbruch 'winget fehlt. Bitte im Microsoft Store "App-Installer" installieren und das Skript neu starten.'
}
Ok (winget --version)

# ---------------------------------------------------------------- Git
Schritt 'Git fuer Windows'
PfadNeuLaden
if (Get-Command git -ErrorAction SilentlyContinue) {
    Ok (git --version)
} else {
    $rc = WingetInstall 'Git.Git' @('--silent')
    PfadNeuLaden
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Abbruch "Git-Installation fehlgeschlagen (Code $rc)."
    }
    Ok (git --version)
}

# ---------------------------------------------------------------- Visual Studio
Schritt 'Visual Studio mit Desktopentwicklung mit C++'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$mitCpp = $null
$irgendeins = $null
if (Test-Path $vswhere) {
    $mitCpp = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
    $irgendeins = & $vswhere -products * -property installationPath | Select-Object -First 1
}
if ($mitCpp) {
    Ok "vorhanden: $mitCpp"
} elseif ($irgendeins) {
    Write-Host '  Visual Studio ist da, aber ohne C++. Arbeitsauslastung wird ergaenzt (dauert einige Minuten) ...'
    $installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vs_installer.exe'
    Start-Process -FilePath $installer -Wait -ArgumentList @(
        'modify', '--installPath', "`"$irgendeins`"",
        '--add', 'Microsoft.VisualStudio.Workload.NativeDesktop', '--includeRecommended',
        '--passive', '--norestart')
    Ok 'C++-Arbeitsauslastung ergaenzt'
} else {
    Write-Host '  Installiere Visual Studio 2022 Community (mehrere GB, kann 20-40 Minuten dauern) ...'
    $rc = WingetInstall 'Microsoft.VisualStudio.2022.Community' @(
        '--override', '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended')
    if ($rc -ne 0) { Write-Host "  Hinweis: winget meldet Code $rc - weiter mit der Pruefung durch flutter doctor." -ForegroundColor Yellow }
}

# ---------------------------------------------------------------- VS Code
if (-not $OhneVSCode) {
    Schritt 'VS Code (optional)'
    PfadNeuLaden
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Ok 'vorhanden'
    } else {
        $rc = WingetInstall 'Microsoft.VisualStudioCode' @('--silent', '--scope', 'user')
        PfadNeuLaden
        if (Get-Command code -ErrorAction SilentlyContinue) {
            & code --install-extension Dart-Code.flutter --force | Out-Null
            Ok 'installiert, Flutter-Erweiterung ergaenzt'
        } else {
            Write-Host "  VS Code nicht installiert (Code $rc) - fuer BauSpur nicht zwingend noetig." -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------- Flutter
Schritt "Flutter SDK in $FlutterDir"
$versionDatei = Join-Path $tools 'flutter-version.txt'
$flutterBat = Join-Path $FlutterDir 'bin\flutter.bat'
if (-not (Test-Path $flutterBat)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $FlutterDir -Parent) | Out-Null
    git clone https://github.com/flutter/flutter.git -b stable $FlutterDir
    if (-not (Test-Path $flutterBat)) { Abbruch 'Flutter konnte nicht heruntergeladen werden.' }
}
if (Test-Path $versionDatei) {
    $soll = (Get-Content $versionDatei -Raw).Trim()
    Write-Host "  Projekt verlangt Flutter $soll"
    git -C $FlutterDir fetch --tags --quiet
    git -C $FlutterDir checkout --quiet $soll
}
$bin = Join-Path $FlutterDir 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ((($userPath -split ';') | ForEach-Object { $_.TrimEnd('\') }) -notcontains $bin) {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $bin), 'User')
    Ok "$bin zum Benutzer-PATH hinzugefuegt"
}
PfadNeuLaden
Write-Host '  Erster Start laedt die Dart-Laufzeit, das dauert einen Moment ...'
flutter --disable-analytics | Out-Null
flutter --version
if ($LASTEXITCODE -ne 0) { Abbruch 'flutter laesst sich nicht starten.' }
if (-not (Test-Path $versionDatei)) {
    $tag = (git -C $FlutterDir describe --tags --exact-match 2>$null)
    if ($tag) { Set-Content -Path $versionDatei -Value $tag -Encoding ascii; Ok "Flutter-Version $tag festgehalten" }
}

Schritt 'flutter doctor'
flutter doctor -v

# ---------------------------------------------------------------- Entwicklermodus
# Flutter-Plugins (path_provider, file_selector) brauchen symbolische Links,
# die Windows nur im Entwicklermodus erlaubt. Ohne ihn scheitern flutter create/pub get.
Schritt 'Windows-Entwicklermodus'
function EntwicklermodusAn {
    $wert = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
        -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue
    return ($wert -and $wert.AllowDevelopmentWithoutDevLicense -eq 1)
}
if (EntwicklermodusAn) {
    Ok 'eingeschaltet'
} else {
    Write-Host '  Der Entwicklermodus ist aus. Die Windows-Einstellungen oeffnen sich gleich:' -ForegroundColor Yellow
    Write-Host '  "Entwicklermodus" einschalten und mit "Ja" bestaetigen.' -ForegroundColor Yellow
    Start-Process 'ms-settings:developers'
    Read-Host '  Danach hier Enter druecken'
    if (-not (EntwicklermodusAn)) { Abbruch 'Entwicklermodus ist weiterhin aus.' }
    Ok 'eingeschaltet'
}

# ---------------------------------------------------------------- Projekt
Schritt 'BauSpur einrichten'
Set-Location $projekt
flutter create --platforms=windows --org de.bauspur --project-name bauspur .
if ($LASTEXITCODE -ne 0) { Abbruch 'flutter create fehlgeschlagen.' }
flutter pub get
if ($LASTEXITCODE -ne 0) { Abbruch 'flutter pub get fehlgeschlagen.' }

Schritt 'Tests'
flutter test
$testsOk = ($LASTEXITCODE -eq 0)

Schritt 'Windows-Programm bauen (Debug)'
flutter build windows --debug
$buildOk = ($LASTEXITCODE -eq 0)

# ---------------------------------------------------------------- Git-Repository
Schritt 'Lokales Git-Repository'
if (-not (Test-Path (Join-Path $projekt '.git'))) {
    git init --quiet --initial-branch=main
    git config user.name 'Tim'
    git config user.email 'bauspur@lokal'
}
$ignore = Join-Path $projekt '.gitignore'
if (-not (Select-String -Path $ignore -Pattern 'tools/install.log' -SimpleMatch -Quiet -ErrorAction SilentlyContinue)) {
    Add-Content -Path $ignore -Value "`n# BauSpur`ntools/install.log"
}
git add -A
git commit --quiet -m 'Grundgeruest Stufe 1, Schritt 1' 2>$null
Ok (git log --oneline -1)

# ---------------------------------------------------------------- Ergebnis
Write-Host ''
Write-Host '============================================================'
if ($testsOk -and $buildOk) {
    Write-Host 'Alles eingerichtet. BauSpur starten mit:' -ForegroundColor Green
    Write-Host "  cd `"$projekt`""
    Write-Host '  flutter run -d windows'
} else {
    Write-Host 'Eingerichtet, aber nicht alles lief durch:' -ForegroundColor Yellow
    if (-not $testsOk) { Write-Host '  - Tests mit Fehlern' -ForegroundColor Yellow }
    if (-not $buildOk) { Write-Host '  - Bauen mit Fehlern' -ForegroundColor Yellow }
    Write-Host "  Bitte den Inhalt von $log an Claude schicken."
}
Write-Host '============================================================'
Stop-Transcript | Out-Null
Read-Host 'Enter zum Schliessen'
