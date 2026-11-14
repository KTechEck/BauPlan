import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Vorschaubild mit Cache auf der Platte: verkleinerte PNG-Kopie im
/// Projektordner unter `.vorschau/` (320 px breit). Beim ersten Mal wird sie
/// erzeugt, danach geht die Galerie auch bei großen Fotos flüssig.
class Vorschaubild extends StatefulWidget {
  const Vorschaubild({super.key, required this.projektOrdner, required this.datei, this.breite, this.hoehe, this.fit = BoxFit.cover});
  final String projektOrdner;
  final String datei; // relativ zum Projektordner
  final double? breite, hoehe;
  final BoxFit fit;

  @override
  State<Vorschaubild> createState() => _VorschaubildState();
}

/// Pfad der Vorschau zu einer Datei (gleicher relativer Pfad, Endung .png).
String vorschauPfad(String projektOrdner, String datei) => p.join(projektOrdner, '.vorschau', '${p.withoutExtension(datei)}.png');

final _inArbeit = <String, Future<bool>>{};

/// Vorschau erzeugen (falls nicht vorhanden oder älter als das Original).
Future<bool> vorschauErzeugen(String projektOrdner, String datei, {int breite = 320}) {
  final ziel = vorschauPfad(projektOrdner, datei);
  return _inArbeit[ziel] ??= () async {
    try {
      final q = File(p.join(projektOrdner, datei));
      final z = File(ziel);
      if (!q.existsSync()) return false;
      if (z.existsSync() && !z.lastModifiedSync().isBefore(q.lastModifiedSync())) return true;
      final codec = await ui.instantiateImageCodec(await q.readAsBytes(), targetWidth: breite);
      final bild = (await codec.getNextFrame()).image;
      final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
      if (daten == null) return false;
      await z.parent.create(recursive: true);
      await z.writeAsBytes(daten.buffer.asUint8List());
      return true;
    } catch (_) {
      return false;
    } finally {
      _inArbeit.remove(ziel);
    }
  }();
}

class _VorschaubildState extends State<Vorschaubild> {
  bool _bereit = false;

  @override
  void initState() {
    super.initState();
    _pruefen();
  }

  @override
  void didUpdateWidget(Vorschaubild alt) {
    super.didUpdateWidget(alt);
    if (alt.datei != widget.datei) {
      _bereit = false;
      _pruefen();
    }
  }

  Future<void> _pruefen() async {
    final ok = await vorschauErzeugen(widget.projektOrdner, widget.datei);
    if (mounted) setState(() => _bereit = ok);
  }

  @override
  Widget build(BuildContext context) {
    final f = File(_bereit ? vorschauPfad(widget.projektOrdner, widget.datei) : p.join(widget.projektOrdner, widget.datei));
    return Image.file(
      f,
      key: ValueKey('${f.path}-$_bereit'),
      width: widget.breite,
      height: widget.hoehe,
      fit: widget.fit,
      cacheWidth: _bereit ? null : 320,
      errorBuilder: (c, e, st) => SizedBox(width: widget.breite, height: widget.hoehe, child: const Center(child: Icon(Icons.image_outlined))),
    );
  }
}
