import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// PDF-Seite als PNG (für die Planvorlage): unter Windows über die
/// eingebaute PDF-Darstellung (Windows.Data.Pdf), ohne Zusatzprogramm.
/// Liefert Seitenbreite in Punkten (1/72 Zoll), Seitenzahl und die Auflösung
/// – daraus ergibt sich bei bekanntem Planmaßstab der Maßstab der Vorlage.
Future<({String png, double breitePt, int seiten, int dpi})?> pdfSeiteAlsPng(String pdf, String png, {int seite = 0, int dpi = 200}) async {
  if (!Platform.isWindows) return null;
  final skript = File(p.join(Directory.systemTemp.path, 'bauspur_pdf_bild.ps1'));
  if (!skript.existsSync() || skript.readAsStringSync() != _skript) skript.writeAsStringSync(_skript);
  try {
    await File(png).parent.create(recursive: true);
    final r = await Process.run(
      'powershell',
      // Windows-Laufzeit verlangt Rückwärtsschrägstriche und absolute Pfade
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', skript.path, File(pdf).absolute.path.replaceAll('/', r'\'), File(png).absolute.path.replaceAll('/', r'\'), '$seite', '$dpi'],
      stdoutEncoding: utf8,
      stderrEncoding: systemEncoding,
    ).timeout(const Duration(seconds: 90));
    final zeile = (r.stdout as String).trim().split('\n').last.trim();
    final teile = zeile.split(' ');
    if (r.exitCode != 0 || teile.length < 2 || !File(png).existsSync()) return null;
    final dip = double.tryParse(teile[0].replaceAll(',', '.')) ?? 0;
    return (png: png, breitePt: dip * 72 / 96, seiten: int.tryParse(teile[1]) ?? 1, dpi: dpi);
  } catch (_) {
    return null;
  }
}

/// µm je Pixel der Vorlage aus Auflösung und Planmaßstab (1:[massstab]).
int umProPxAusMassstab(int dpi, int massstab) => (25400 / dpi * massstab).round();

const _skript = r'''
param([string]$pdf, [string]$png, [int]$seite = 0, [int]$dpi = 200)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.StorageFolder, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime]
$null = [Windows.Data.Pdf.PdfPageRenderOptions, Windows.Data.Pdf, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapEncoder, Windows.Graphics, ContentType = WindowsRuntime]
$m = [System.WindowsRuntimeSystemExtensions].GetMethods()
$opT = ($m | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$acT = ($m | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function Warte($op, $typ) { $t = $opT.MakeGenericMethod($typ).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
function WarteAktion($op) { $t = $acT.Invoke($null, @($op)); $t.Wait(-1) | Out-Null }
$datei = Warte ([Windows.Storage.StorageFile]::GetFileFromPathAsync($pdf)) ([Windows.Storage.StorageFile])
$doc = Warte ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($datei)) ([Windows.Data.Pdf.PdfDocument])
$s = $doc.GetPage([uint32]$seite)
$ordner = Warte ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync([System.IO.Path]::GetDirectoryName($png))) ([Windows.Storage.StorageFolder])
$ziel = Warte ($ordner.CreateFileAsync([System.IO.Path]::GetFileName($png), [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
$strom = Warte ($ziel.OpenAsync([Windows.Storage.FileAccessMode]::ReadWrite)) ([Windows.Storage.Streams.IRandomAccessStream])
$opt = New-Object Windows.Data.Pdf.PdfPageRenderOptions
$opt.DestinationWidth = [uint32]([Math]::Round($s.Size.Width * $dpi / 96))
$opt.BitmapEncoderId = [Windows.Graphics.Imaging.BitmapEncoder]::PngEncoderId
WarteAktion ($s.RenderToStreamAsync($strom, $opt))
$strom.Dispose()
Write-Output ("{0} {1}" -f $s.Size.Width.ToString([System.Globalization.CultureInfo]::InvariantCulture), $doc.PageCount)
''';
