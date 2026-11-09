# Entwicklungsumgebung und Umzug auf einen anderen PC

## Was wo liegt

| Was | Ort | Beim Umzug |
| --- | --- | --- |
| Quellcode BauSpur | `Dokumente\BauSpur` (eigenes Git-Repository) | Ordner kopieren oder klonen |
| Flutter SDK | `%USERPROFILE%\dev\flutter` | wird vom Skript neu installiert, gleiche Version |
| Flutter-Version des Projekts | `tools\flutter-version.txt` | liegt im Projekt, wandert mit |
| Git, Visual Studio, VS Code | Programme | werden vom Skript neu installiert |
| Projektdaten (Häuser) | Projektordner auf der Synology | bleiben, wo sie sind |
| Programmeinstellungen BauSpur | `%APPDATA%\de.bauspur\bauspur\einstellungen.json` | optional mitkopieren (nur Liste zuletzt geöffneter Projekte) |

## Neuer PC – in drei Schritten

1. `BauSpur`-Ordner auf den neuen PC bringen:
   - kopieren (USB, NAS), oder
   - später, wenn ein zentrales Repository existiert: `git clone <adresse> BauSpur`
2. `Installieren.cmd` im BauSpur-Ordner doppelklicken.
3. `flutter run -d windows`.

## Sicherung des Quellcodes

Der Code ist ein lokales Git-Repository. Empfehlung, sobald die Synology da ist:
ein zentrales Repository auf dem NAS anlegen und dorthin sichern.

```powershell
# einmalig, Pfad anpassen
git init --bare \\NAS\BauSpur\_code\bauspur.git
git remote add nas \\NAS\BauSpur\_code\bauspur.git
git push -u nas main
# danach nach jeder Änderung
git push
```

Auf dem neuen PC dann einfach: `git clone \\NAS\BauSpur\_code\bauspur.git BauSpur`.
