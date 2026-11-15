import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/speicher.dart';
import '../data/sync.dart';
import 'app_state.dart';

/// Zustand der Live-Verbindung (für die Anzeige).
typedef LiveZustand = ({bool verbunden, int wartend, DateTime? zuletzt, String? fehler, int konflikte});

/// Echtzeit-Abgleich auf dem iPad: alle paar Sekunden und kurz nach jeder
/// Änderung eigene Änderungen an den PC, dessen Änderungen hierher. Ohne
/// Netz wird weitergearbeitet; die Änderungen warten und gehen beim nächsten
/// Kontakt mit.
class LiveSync {
  LiveSync(this.state, this.stand);
  final AppState state;
  final SyncStand stand;
  Timer? _takt, _bald;
  final _geladen = <String>{};
  final zustand = ValueNotifier<LiveZustand>((verbunden: false, wartend: 0, zuletzt: null, fehler: null, konflikte: 0));

  void starten() {
    final st = state.store;
    if (st == null) return;
    if (stand.eigen < 0) {
      stand.eigen = syncStand(st.db);
      stand.schreiben(st.ordner);
    }
    _takt = Timer.periodic(const Duration(seconds: 3), (_) => abgleichen());
    _bald = Timer(Duration.zero, abgleichen);
  }

  void stoppen() {
    _takt?.cancel();
    _bald?.cancel();
  }

  /// Nach einer Änderung: kurz warten (mehrere Klicks bündeln), dann abgleichen.
  void bald() {
    _bald?.cancel();
    _bald = Timer(const Duration(milliseconds: 400), abgleichen);
  }

  Future<void>? _lauf;

  /// Abgleichen; läuft schon einer, danach noch einmal (Aufrufer wartet).
  Future<void> abgleichen() async {
    while (_lauf != null) {
      await _lauf;
    }
    final c = Completer<void>();
    _lauf = c.future;
    try {
      await _einmal();
    } finally {
      _lauf = null;
      c.complete();
    }
  }

  Future<void> _einmal() async {
    final st = state.store;
    final adresse = stand.adresse;
    if (st == null || adresse == null) return;
    final pc = PcSpeicher(adresse, code: stand.code ?? '');
    try {
      // 1. neue Dateien (Fotos, Dokumente) hoch
      final start = DateTime.now();
      for (final rel in geaenderteDateien(st.ordner, stand.eigeneDateienSeit)) {
        if (_geladen.remove(rel)) continue;
        await pc.projektDateiHoch(stand.geraet, rel, await File(p.join(st.ordner, rel)).readAsBytes());
      }
      // 2. eigene Änderungen schicken, die des PCs bekommen
      final eigen = aenderungenSeit(st, stand.eigen);
      final antwort = await pc.projektSync(stand.geraet, {
        'seit': stand.pc,
        'aenderungen': eigen.aenderungen,
        if (stand.dateienSeit != null) 'dateien_seit': stand.dateienSeit!.toIso8601String(),
      });
      // 3. Änderungen vom PC übernehmen – außer Datensätze, die hier seitdem schon wieder geändert wurden
      final neuHier = {for (final a in aenderungenSeit(st, eigen.bis).aenderungen) '${a['t']}|${a['id']}'};
      final rein = [
        for (final a in (antwort['aenderungen'] as List? ?? const []))
          if (!neuHier.contains('${(a as Map)['t']}|${a['id']}')) Map<String, dynamic>.from(a)
      ];
      if (rein.isNotEmpty) aenderungenAnwenden(st, rein, stumm: true);
      // 4. neue Dateien vom PC
      final dateien = [for (final d in (antwort['dateien'] as List? ?? const [])) '$d'];
      for (final rel in dateien) {
        final b = await pc.projektDateiRunter(stand.geraet, rel);
        if (b == null) continue;
        final f = File(p.join(st.ordner, rel));
        await f.parent.create(recursive: true);
        await f.writeAsBytes(b);
        _geladen.add(rel);
      }
      stand
        ..pc = (antwort['bis'] as num?)?.toInt() ?? stand.pc
        ..eigen = eigen.bis
        ..dateienSeit = DateTime.tryParse('${antwort['zeit'] ?? ''}') ?? stand.dateienSeit
        ..eigeneDateienSeit = start;
      stand.schreiben(st.ordner);
      zustand.value = (verbunden: true, wartend: 0, zuletzt: DateTime.now(), fehler: null, konflikte: zustand.value.konflikte + ((antwort['konflikte'] as num?)?.toInt() ?? 0));
      if (rein.isNotEmpty || dateien.isNotEmpty) state.geaendert(vonAbgleich: true);
    } catch (e) {
      final wartend = aenderungenSeit(st, stand.eigen).aenderungen.length;
      zustand.value = (verbunden: false, wartend: wartend, zuletzt: zustand.value.zuletzt, fehler: '$e'.replaceFirst('Bad state: ', ''), konflikte: zustand.value.konflikte);
    }
  }
}
