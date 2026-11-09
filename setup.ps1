# BauSpur - einmalige Einrichtung auf einem Windows-PC
# Aufruf in PowerShell im Ordner BauSpur:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "1/4 Flutter pruefen ..." -ForegroundColor Cyan
flutter --version

Write-Host "2/4 Windows-Projektdateien ergaenzen (vorhandene Dateien bleiben unveraendert) ..." -ForegroundColor Cyan
flutter create --platforms=windows --org de.bauspur --project-name bauspur .

Write-Host "3/4 Pakete laden ..." -ForegroundColor Cyan
flutter pub get

Write-Host "4/4 Tests ausfuehren ..." -ForegroundColor Cyan
flutter test

Write-Host ""
Write-Host "Fertig. Starten mit:  flutter run -d windows" -ForegroundColor Green
