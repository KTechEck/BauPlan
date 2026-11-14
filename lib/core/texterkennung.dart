import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Texterkennung ohne Internet und ohne KI: unter Windows über die
/// eingebaute Windows-Texterkennung (Windows.Media.Ocr, Sprache des
/// Benutzerprofils). Liefert die erkannten Zeilen oder null, wenn es nicht
/// geht (anderes System, keine Sprachdaten).
Future<String?> textErkennen(String bildPfad) async {
  if (!Platform.isWindows) return null;
  final skript = File(p.join(Directory.systemTemp.path, 'bauspur_texterkennung.ps1'));
  if (!skript.existsSync() || skript.readAsStringSync() != _skript) skript.writeAsStringSync(_skript);
  try {
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', skript.path, bildPfad],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 60));
    final text = (r.stdout as String).trim();
    if (r.exitCode != 0 || text.isEmpty) return null;
    return texterkennungBereinigen(text);
  } catch (_) {
    return null;
  }
}

const _skript = r'''
param([string]$pfad)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Warte($op, $typ) { $t = $asTask.MakeGenericMethod($typ).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
$datei = Warte ([Windows.Storage.StorageFile]::GetFileFromPathAsync($pfad)) ([Windows.Storage.StorageFile])
$strom = Warte ($datei.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$dec = Warte ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($strom)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bild = Warte ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($engine -eq $null) { exit 2 }
$erg = Warte ($engine.RecognizeAsync($bild)) ([Windows.Media.Ocr.OcrResult])
# Wörter nach Zeilenhöhe gruppieren, damit Preise rechts zur Artikelzeile kommen
$woerter = @()
foreach ($z in $erg.Lines) { foreach ($w in $z.Words) { $woerter += [pscustomobject]@{ x = $w.BoundingRect.X; y = $w.BoundingRect.Y + $w.BoundingRect.Height / 2; h = $w.BoundingRect.Height; t = $w.Text } } }
$woerter = $woerter | Sort-Object y
$zeilen = @(); $akt = @(); $ya = $null
foreach ($w in $woerter) {
  if ($ya -ne $null -and [math]::Abs($w.y - $ya) -gt ($w.h * 0.6)) { $zeilen += ,($akt | Sort-Object x); $akt = @() }
  if ($akt.Count -eq 0) { $ya = $w.y }
  $akt += $w
}
if ($akt.Count -gt 0) { $zeilen += ,($akt | Sort-Object x) }
foreach ($z in $zeilen) { ($z | ForEach-Object { $_.t }) -join ' ' }
''';

/// Typische Fehler der Texterkennung auf Kassenzetteln glätten:
/// „17, 80“ → „17,80“, „14. 11. 2026“ → „14.11.2026“, „2x“/„2 X“ → „2 x“.
String texterkennungBereinigen(String t) => t
    .replaceAllMapped(RegExp(r'(\d),\s+(\d{2})(?!\d)'), (m) => '${m[1]},${m[2]}')
    .replaceAllMapped(RegExp(r'(\d{1,2})\.\s+(\d{1,2})\.\s+(\d{2,4})'), (m) => '${m[1]}.${m[2]}.${m[3]}')
    .replaceAllMapped(RegExp(r'^(\d+)\s*[xX×]\s+', multiLine: true), (m) => '${m[1]} x ');
