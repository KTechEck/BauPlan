import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/raumerkennung.dart';
import '../../core/wandmasse.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../floorplan/floorplan_painter.dart';
import '../installation/installation_page.dart' show ObjektPainter;
import '../project_tree.dart';
import '../tastenkuerzel.dart';
import '../widgets.dart';
import 'foto_markieren_page.dart';

/// Modul Fotos: Fotos importieren, im Grundriss mit Blickrichtung verorten
/// und Objekten zuordnen (z. B. Leerrohre vor dem Estrich).
class FotosPage extends StatefulWidget {
  const FotosPage({super.key, required this.state});
  final AppState state;

  @override
  State<FotosPage> createState() => _FotosPageState();
}

class _FotosPageState extends State<FotosPage> {
  final _fokus = FocusNode();
  bool _ansichtZiehen = false; // Leertaste + Ziehen
  double _massstab = 0.08;
  Offset _verschiebung = const Offset(120, 120);
  Size _flaeche = Size.zero;
  bool _eingepasst = false;
  String? _auswahl; // Medium-ID
  int _modus = 0; // 0 nichts, 1 Position setzen, 2 Blickrichtung setzen
  Offset? _maus;
  final List<VoidCallback> _rueckgaengig = [];
  String? _geschossBeiLetztemBuild;

  // Daten (je Revision)
  (int, String?)? _stand;
  late List<Wand> _waende;
  late Map<String, List<Offset>> _umrisse;
  late List<Raum> _raeume;
  late List<Oeffnung> _oeffnungen;
  late List<Foto> _fotos;
  late List<Objekt> _objekte;
  late Map<String, Objekttyp> _typen;
  late Map<String, Gewerk> _gewerke;

  AppState get _s => widget.state;

  @override
  void dispose() {
    _fokus.dispose();
    super.dispose();
  }

  void _laden() {
    final stand = (_s.revision, _s.geschossId);
    if (_stand == stand) return;
    _stand = stand;
    final store = _s.store!;
    final g = _s.geschossId;
    _waende = g == null ? [] : store.waende(g);
    final global = store.einstellung<bool>('ecken_verbinden') ?? true;
    final achsen = [for (final w in _waende) w.achse];
    final verb = [for (final w in _waende) w.verbinden ?? global];
    final nachbarn = [
      for (var i = 0; i < _waende.length; i++)
        if (verb[i]) achsen[i]
    ];
    _umrisse = {
      for (var i = 0; i < _waende.length; i++)
        _waende[i].id: [for (final q in wandUmriss(achsen[i], verb[i] ? nachbarn : [achsen[i]])) Offset(q.x, q.y)],
    };
    _raeume = g == null ? [] : store.raeume(g);
    _oeffnungen = g == null ? [] : store.oeffnungen(g);
    _fotos = g == null ? [] : store.fotos(g);
    _objekte = g == null ? [] : store.objekte(g);
    _typen = {for (final t in store.objekttypen()) t.id: t};
    _gewerke = {for (final x in store.gewerke()) x.id: x};
  }

  Offset _zuWelt(Offset b) => (b - _verschiebung) / _massstab;
  String _pfad(Foto f) => p.join(_s.store!.ordner, f.datei);

  /// Fotos, die zur Auswahl im Projektbaum passen (Raum gewählt → nur dieser Raum).
  List<Foto> get _sichtbareFotos =>
      _s.raumId == null ? _fotos : _fotos.where((f) => f.raumId == _s.raumId).toList();

  String? _raumBei(Offset w) {
    final q = Punkt(w.dx, w.dy);
    for (final r in _raeume) {
      if (r.umriss != null && punktInPolygon(q, r.umriss!)) return r.id;
    }
    return null;
  }

  Future<void> _importieren() async {
    if (_s.geschossId == null) return;
    final dateien = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(label: 'Fotos', extensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp']),
    ]);
    if (dateien.isEmpty) return;
    final store = _s.store!;
    final ids = [
      for (final d in dateien) store.fotoImportieren(d.path, geschossId: _s.geschossId!, raumId: _s.raumId)
    ];
    _rueckgaengig.add(() {
      for (final id in ids) {
        store.fotoLoeschen(id);
      }
    });
    _s.geaendert();
    if (!mounted) return;
    setState(() {
      _auswahl = ids.first;
      _modus = 1;
    });
    zeigeHinweis(context, '${ids.length} Foto(s) importiert. Jetzt im Grundriss klicken, wo das Foto aufgenommen wurde.');
  }

  void _markerAendern(Foto f, Map<String, Object?> felder) {
    final store = _s.store!;
    final alt = store.fotoMarkerAendern(f.id, felder);
    if (alt.isEmpty) return;
    _rueckgaengig.add(() => store.fotoMarkerAendern(f.id, alt));
    _s.geaendert();
  }

  void _klick(Offset bildschirm) {
    _fokus.requestFocus();
    if (_s.geschossId == null) return;
    final welt = _zuWelt(bildschirm);
    final f = _fotos.where((e) => e.id == _auswahl).firstOrNull;
    if (f != null && _modus == 1) {
      final raum = _raumBei(welt);
      _markerAendern(f, {'x_mm': welt.dx.round(), 'y_mm': welt.dy.round(), 'raum_id': raum ?? f.raumId});
      setState(() => _modus = 2);
      return;
    }
    if (f != null && _modus == 2 && f.verortet) {
      final d = welt - Offset(f.x!.toDouble(), f.y!.toDouble());
      if (d.distance > 1) {
        var w = (math.atan2(-d.dy, d.dx) * 180 / math.pi).round();
        if (w < 0) w += 360;
        _markerAendern(f, {'richtung': w});
      }
      setState(() => _modus = 0);
      // nächstes unverortetes Foto gleich anbieten
      final naechstes = _fotos.where((e) => !e.verortet && e.id != f.id).firstOrNull;
      if (naechstes != null) {
        setState(() {
          _auswahl = naechstes.id;
          _modus = 1;
        });
      }
      return;
    }
    // Marker anklicken
    String? treffer;
    var bester = 12 / _massstab;
    for (final e in _fotos) {
      if (!e.verortet) continue;
      final a = (Offset(e.x!.toDouble(), e.y!.toDouble()) - welt).distance;
      if (a < bester) {
        bester = a;
        treffer = e.id;
      }
    }
    setState(() {
      _auswahl = treffer;
      _modus = 0;
    });
  }

  void _einpassen() {
    final pts = [
      for (final w in _waende) ...[Offset(w.x1.toDouble(), w.y1.toDouble()), Offset(w.x2.toDouble(), w.y2.toDouble())],
      for (final f in _fotos)
        if (f.verortet) Offset(f.x!.toDouble(), f.y!.toDouble()),
    ];
    if (pts.isEmpty || _flaeche.isEmpty) return;
    final r = pts.skip(1).fold(Rect.fromPoints(pts.first, pts.first), (Rect a, q) => a.expandToInclude(Rect.fromPoints(q, q)));
    final b = math.max(1000.0, r.width), h = math.max(1000.0, r.height);
    final m = math.min((_flaeche.width - 120) / b, (_flaeche.height - 120) / h).clamp(0.005, 2.0).toDouble();
    setState(() {
      _massstab = m;
      _verschiebung = Offset((_flaeche.width - b * m) / 2 - r.left * m, (_flaeche.height - h * m) / 2 - r.top * m);
    });
  }

  KeyEventResult _taste(FocusNode n, KeyEvent e) {
    if (e is KeyUpEvent && e.logicalKey == LogicalKeyboardKey.space) {
      _ansichtZiehen = false;
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.f1:
        tastenkuerzelZeigen(context);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _ansichtZiehen = true;
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        setState(() => _verschiebung += const Offset(80, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        setState(() => _verschiebung -= const Offset(80, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _verschiebung += const Offset(0, 80));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        setState(() => _verschiebung -= const Offset(0, 80));
        return KeyEventResult.handled;
      default:
    }
    final k = e.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed && k == LogicalKeyboardKey.keyZ) {
      if (_rueckgaengig.isNotEmpty) {
        _rueckgaengig.removeLast()();
        _s.geaendert();
      }
      return KeyEventResult.handled;
    }
    if (!HardwareKeyboard.instance.isControlPressed && k == LogicalKeyboardKey.keyI) {
      _importieren();
      return KeyEventResult.handled;
    }
    if (!HardwareKeyboard.instance.isControlPressed && k == LogicalKeyboardKey.keyV) {
      setState(() => _modus = 0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(() => _modus = 0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete && _auswahl != null) {
      _loeschen(_auswahl!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _loeschen(String id) {
    final store = _s.store!;
    store.fotoLoeschen(id);
    _rueckgaengig.add(() => store.fotoWiederherstellen(id));
    setState(() => _auswahl = null);
    _s.geaendert();
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_geschossBeiLetztemBuild != _s.geschossId) {
      _geschossBeiLetztemBuild = _s.geschossId;
      _auswahl = null;
      _modus = 0;
      _eingepasst = false;
      _rueckgaengig.clear();
    }
    _laden();
    final f = _fotos.where((e) => e.id == _auswahl).firstOrNull;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ProjectTree(state: _s),
      Expanded(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(
                onPressed: _s.geschossId == null ? null : _importieren,
                icon: const Icon(Sym.importieren),
                label: const Text('Fotos importieren'),
              ),
              OutlinedButton.icon(
                onPressed: _einpassen,
                icon: const Icon(Sym.allesZeigen, size: 18),
                label: const Text('Alles zeigen'),
              ),
              Text(
                '${_fotos.length} Fotos im Geschoss · ${_fotos.where((e) => !e.verortet).length} noch nicht verortet',
                style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
              ),
            ]),
          ),
          Expanded(child: _s.geschossId == null ? const Center(child: Text('Links ein Geschoss wählen.')) : _plan(f)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            color: Colors.white,
            child: Text(
              switch (_modus) {
                1 => 'Klicken, wo das Foto aufgenommen wurde · Esc bricht ab',
                2 => 'Klicken, wohin die Kamera geschaut hat · Esc überspringt',
                _ => 'Marker anklicken · Entf löscht · Strg+Z rückgängig · rechte Maustaste verschiebt, Mausrad zoomt',
              },
              style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
            ),
          ),
        ]),
      ),
      Container(
        width: 340,
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: BsFarben.rand))),
        child: Material(color: Colors.white, child: f == null ? _galerie() : _details(f)),
      ),
    ]);
  }

  Widget _plan(Foto? gewaehlt) {
    return LayoutBuilder(builder: (context, c) {
      _flaeche = Size(c.maxWidth, c.maxHeight);
      if (!_eingepasst) {
        _eingepasst = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _einpassen();
        });
      }
      return Focus(
        focusNode: _fokus,
        autofocus: true,
        onKeyEvent: _taste,
        child: MouseRegion(
          cursor: _modus == 0 ? SystemMouseCursors.basic : SystemMouseCursors.precise,
          onHover: (e) => setState(() => _maus = _zuWelt(e.localPosition)),
          onExit: (_) => setState(() => _maus = null),
          child: Listener(
            onPointerDown: (e) {
              if (e.buttons == kPrimaryMouseButton && !_ansichtZiehen) _klick(e.localPosition);
            },
            onPointerMove: (e) {
              if ((e.buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0 ||
                  (_ansichtZiehen && (e.buttons & kPrimaryMouseButton) != 0)) {
                setState(() => _verschiebung += e.delta);
              }
            },
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                if (HardwareKeyboard.instance.isShiftPressed) {
                  setState(() => _verschiebung -= Offset(e.scrollDelta.dy, e.scrollDelta.dx));
                  return;
                }
                final fak = e.scrollDelta.dy > 0 ? 0.88 : 1 / 0.88;
                final neu = (_massstab * fak).clamp(0.005, 2.0).toDouble();
                final w = _zuWelt(e.localPosition);
                setState(() {
                  _massstab = neu;
                  _verschiebung = e.localPosition - w * neu;
                });
              }
            },
            onPointerPanZoomUpdate: (e) => setState(() => _verschiebung += e.panDelta),
            child: ClipRect(
              child: Stack(children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: FloorplanPainter(
                      waende: _waende,
                      raeume: [
                        for (final r in _raeume)
                          if (r.umriss != null)
                            RaumBild(
                              umriss: [for (final q in r.umriss!) Offset(q.x, q.y)],
                              beschriftung: r.name,
                              innenpunkt: Offset(punktImInneren(r.umriss!).x, punktImInneren(r.umriss!).y),
                              ausgewaehlt: r.id == _s.raumId,
                            ),
                      ],
                      umrisse: _umrisse,
                      schichten: const {},
                      massstab: _massstab,
                      verschiebung: _verschiebung,
                      auswahl: const {},
                      kettenStart: null,
                      maus: null,
                      vorschauDicke: 0,
                      massVoreinstellung: MassAnzeige.keine,
                      oeffnungen: _oeffnungen,
                    ),
                  ),
                ),
                // Objekte, die das gewählte Foto zeigt, hervorheben
                if (gewaehlt != null && gewaehlt.objektIds.isNotEmpty)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ObjektPainter(
                        objekte: [for (final o in _objekte) if (gewaehlt.objektIds.contains(o.id)) o],
                        typen: _typen,
                        gewerke: _gewerke,
                        massstab: _massstab,
                        verschiebung: _verschiebung,
                        auswahl: null,
                        entwurf: const [],
                        entwurfFarbe: null,
                        entwurfFlaeche: false,
                        maus: null,
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FotoPainter(
                      fotos: [for (final e in _sichtbareFotos) if (e.verortet) e],
                      auswahl: _auswahl,
                      massstab: _massstab,
                      verschiebung: _verschiebung,
                      vorschauRichtung: _modus == 2 && gewaehlt != null && gewaehlt.verortet ? _maus : null,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _galerie() {
    final fotos = _sichtbareFotos;
    final raum = _raeume.where((r) => r.id == _s.raumId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(raum == null ? 'Alle Fotos des Geschosses' : 'Fotos · ${raum.name}',
            style: Theme.of(context).textTheme.titleMedium),
      ),
      if (fotos.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Noch keine Fotos. Oben „Fotos importieren“ – sie landen lesbar sortiert unter '
              'medien/Geschoss/Raum/ im Projektordner.'),
        ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8),
          itemCount: fotos.length,
          itemBuilder: (_, i) {
            final f = fotos[i];
            return InkWell(
              onTap: () => setState(() {
                _auswahl = f.id;
                _modus = f.verortet ? 0 : 1;
              }),
              child: Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(_pfad(f)), fit: BoxFit.cover, cacheWidth: 320,
                      errorBuilder: (_, __, ___) => Container(color: BsFarben.flaeche, child: const Icon(Icons.image_not_supported_outlined))),
                ),
                if (!f.verortet)
                  const Positioned(
                    right: 4,
                    top: 4,
                    child: Tooltip(message: 'noch nicht verortet', child: Icon(Icons.location_off, color: BsFarben.akzent, size: 20)),
                  ),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _details(Foto f) {
    final store = _s.store!;
    final raum = _raeume.where((r) => r.id == f.raumId).firstOrNull;
    final lokal = f.aufnahme.toLocal();
    final datum = '${lokal.day}.${lokal.month}.${lokal.year} ${lokal.hour}:${lokal.minute.toString().padLeft(2, '0')}';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => _auswahl = null), icon: const Icon(Icons.arrow_back), tooltip: 'zur Galerie'),
        Expanded(child: Text(p.basename(f.datei), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
      ]),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(_pfad(f)), fit: BoxFit.contain, cacheWidth: 900,
            errorBuilder: (_, __, ___) => const SizedBox(height: 120, child: Center(child: Text('Vorschau nicht möglich (z. B. HEIC)')))),
      ),
      const SizedBox(height: 10),
      Text('$datum · ${f.autor}', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Text(raum == null ? 'kein Raum' : 'Raum: ${raum.name}', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: [
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => FotoMarkierenPage(state: _s, mediumId: f.id, datei: _pfad(f)))),
          icon: const Icon(Icons.draw_outlined, size: 18),
          label: Text('Markieren${store.fotoMarkierungen(f.id).isEmpty ? '' : ' (${store.fotoMarkierungen(f.id).length})'}'),
        ),
        if (store.fotoIstPanorama(f.id))
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PanoramaPage(datei: _pfad(f), titel: p.basename(f.datei)))),
            icon: const Icon(Icons.threesixty, size: 18),
            label: const Text('360° ansehen'),
          ),
      ]),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('360°-Panorama'),
        subtitle: const Text('equirektangulares Rundumfoto, z. B. von einer 360°-Kamera'),
        value: store.fotoIstPanorama(f.id),
        onChanged: (v) {
          store.fotoPanoramaSetzen(f.id, v);
          _s.geaendert();
        },
      ),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _modus = 1),
          icon: const Icon(Sym.verorten, size: 18),
          label: Text(f.verortet ? 'neu verorten' : 'im Grundriss verorten'),
        ),
        if (f.verortet)
          OutlinedButton.icon(
            onPressed: () => setState(() => _modus = 2),
            icon: const Icon(Sym.richtung, size: 18),
            label: Text(f.richtung == null ? 'Blickrichtung setzen' : 'Blickrichtung ${f.richtung}°'),
          ),
      ]),
      const SizedBox(height: 12),
      TextFormField(
        key: ValueKey('notiz-${f.id}-${f.notiz}'),
        initialValue: f.notiz ?? '',
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(labelText: 'Notiz', helperText: 'Enter in neuer Zeile mit Umschalt, Speichern mit Strg+Enter oder Feld verlassen'),
        onChanged: (v) => _notizEntwurf = v,
        onEditingComplete: () => _notizSpeichern(f),
        onTapOutside: (_) => _notizSpeichern(f),
      ),
      const SizedBox(height: 12),
      Text('Zeigt Objekte', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      if (_objekte.isEmpty)
        const Text('Im Geschoss gibt es noch keine Objekte (Modul Installation).', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      for (final o in _objekteNahe(f))
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: f.objektIds.contains(o.id),
          secondary: Container(width: 10, height: 10, color: Color(_gewerke[_typen[o.typId]?.gewerkId]?.farbe ?? 0xFF888888)),
          title: Text(o.kennung, style: const TextStyle(fontSize: 13)),
          subtitle: Text(_typen[o.typId]?.name ?? '', style: const TextStyle(fontSize: 11)),
          onChanged: (v) {
            store.fotoObjektZuordnen(f.id, o.id, v == true);
            _rueckgaengig.add(() => store.fotoObjektZuordnen(f.id, o.id, v != true));
            _s.geaendert();
          },
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: () => _loeschen(f.id), icon: const Icon(Sym.loeschen), label: const Text('Foto löschen (Entf)')),
    ]);
  }

  String? _notizEntwurf;
  void _notizSpeichern(Foto f) {
    final n = _notizEntwurf;
    if (n == null || n == (f.notiz ?? '')) return;
    _notizEntwurf = null;
    final store = _s.store!;
    final alt = f.notiz;
    store.fotoNotizSetzen(f.id, n.trim().isEmpty ? null : n.trim());
    _rueckgaengig.add(() => store.fotoNotizSetzen(f.id, alt));
    _s.geaendert();
  }

  /// Objekte im selben Raum (oder in der Nähe des Markers) zuerst, zugeordnete immer.
  List<Objekt> _objekteNahe(Foto f) {
    final liste = [..._objekte];
    double abstand(Objekt o) {
      if (f.objektIds.contains(o.id)) return -1;
      if (!f.verortet || o.punkte.isEmpty) return o.raumId == f.raumId ? 0 : 1e12;
      final q = Offset(o.punkte.first.x, o.punkte.first.y);
      return (q - Offset(f.x!.toDouble(), f.y!.toDouble())).distance;
    }

    liste.sort((a, b) => abstand(a).compareTo(abstand(b)));
    return liste.take(12).toList();
  }
}

/// Fotomarker: Kamerapunkt mit Blickrichtungskegel.
class _FotoPainter extends CustomPainter {
  _FotoPainter({
    required this.fotos,
    required this.auswahl,
    required this.massstab,
    required this.verschiebung,
    required this.vorschauRichtung,
  });

  final List<Foto> fotos;
  final String? auswahl;
  final double massstab;
  final Offset verschiebung;
  final Offset? vorschauRichtung;

  Offset _s(Offset w) => w * massstab + verschiebung;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in fotos) {
      final c = _s(Offset(f.x!.toDouble(), f.y!.toDouble()));
      final gewaehlt = f.id == auswahl;
      final farbe = gewaehlt ? BsFarben.akzent : const Color(0xFF3B5BA9);
      double? richtung = f.richtung?.toDouble();
      final v = vorschauRichtung;
      if (gewaehlt && v != null) {
        final d = v - Offset(f.x!.toDouble(), f.y!.toDouble());
        richtung = math.atan2(-d.dy, d.dx) * 180 / math.pi;
      }
      if (richtung != null) {
        final w = -richtung * math.pi / 180; // Bildschirm: y nach unten
        const oeffnung = 0.45;
        const r = 34.0;
        final kegel = Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + math.cos(w - oeffnung) * r, c.dy + math.sin(w - oeffnung) * r)
          ..arcTo(Rect.fromCircle(center: c, radius: r), w - oeffnung, 2 * oeffnung, false)
          ..close();
        canvas.drawPath(kegel, Paint()..color = farbe.withValues(alpha: 0.25));
      }
      canvas.drawCircle(c, gewaehlt ? 8 : 6, Paint()..color = farbe);
      canvas.drawCircle(c, gewaehlt ? 8 : 6, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _FotoPainter old) => true;
}
