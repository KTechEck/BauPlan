import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/glossar.dart';
import '../state/app_state.dart';

/// Ob das Hilfe-Panel rechts offen ist (je PC gemerkt).
final hilfePanelOffen = ValueNotifier<bool>(false);

bool _geladen = false;

/// Einmal beim ersten Aufbau die gemerkte Einstellung übernehmen.
void hilfePanelLaden(AppState s) {
  if (_geladen) return;
  _geladen = true;
  hilfePanelOffen.value = s.settings.darstellung['hilfe_panel'] == true;
}

void hilfePanelUmschalten(AppState s) {
  hilfePanelOffen.value = !hilfePanelOffen.value;
  s.settings.darstellung['hilfe_panel'] = hilfePanelOffen.value;
  s.settings.speichern();
}

/// Hilfe rechts: erklärt Fachbegriffe des aktuellen Bereichs. Klickt man in
/// ein Eingabefeld, steht die passende Erklärung oben („Gerade im Feld“).
class HilfePanel extends StatefulWidget {
  const HilfePanel({super.key, required this.state});
  final AppState state;

  @override
  State<HilfePanel> createState() => _HilfePanelState();
}

class _HilfePanelState extends State<HilfePanel> {
  final _suche = TextEditingController();
  Begriff? _feld;
  String? _feldText;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_fokus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_fokus);
    _suche.dispose();
    super.dispose();
  }

  void _fokus() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return;
    final tf = ctx.findAncestorWidgetOfExactType<TextField>();
    final d = tf?.decoration;
    final text = d?.labelText ?? d?.hintText ?? d?.helperText;
    if (text == null || text == _feldText) return;
    final b = begriffZuFeld(text);
    if (!mounted) return;
    setState(() {
      _feldText = text;
      if (b != null) _feld = b;
    });
  }

  Widget _eintrag(Begriff b, {bool offen = false}) => ExpansionTile(
        key: PageStorageKey('hilfe-${b.name}-$offen'),
        initiallyExpanded: offen,
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        children: [
          Text(b.kurz, style: const TextStyle(fontSize: 12.5, height: 1.35)),
          if (b.einheit.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Einheit: ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: b.einheit),
            ]), style: const TextStyle(fontSize: 12)),
          ],
          if (b.eingabe.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Eingeben: ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: b.eingabe),
            ]), style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final q = _suche.text.trim();
    final bereiche = glossarJeModul[widget.state.modul.name] ?? const <String>[];
    final liste = q.isNotEmpty
        ? glossar.where((b) => b.passt(q)).toList()
        : [
            for (final br in bereiche) ...glossar.where((b) => b.bereich == br),
          ];
    final andere = q.isEmpty ? [for (final b in glossar) if (!bereiche.contains(b.bereich)) b] : const <Begriff>[];
    return Material(
      color: Colors.white,
      shape: const Border(left: BorderSide(color: BsFarben.rand)),
      child: SizedBox(
      width: 320,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
          child: Row(children: [
            const Icon(Icons.help_outline, size: 18, color: BsFarben.akzentDunkel),
            const SizedBox(width: 6),
            const Expanded(child: Text('Hilfe: Begriffe und Werte', style: TextStyle(fontWeight: FontWeight.w700))),
            IconButton(tooltip: 'Hilfe ausblenden', icon: const Icon(Icons.close, size: 18), onPressed: () => hilfePanelUmschalten(widget.state)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: TextField(
            controller: _suche,
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Begriff suchen, z. B. kv, Uw, Spreizung'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: ListView(children: [
            if (_feld case final f? when q.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Material(
                color: BsFarben.akzentHell.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    child: Text('Gerade im Feld${_feldText == null ? '' : ' „$_feldText“'}', style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
                  ),
                  _eintrag(f, offen: true),
                ]),
              ),
              ),
            ],
            if (liste.isEmpty && q.isNotEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Nichts gefunden.')),
            for (final (i, b) in liste.indexed) ...[
              if (i == 0 || liste[i - 1].bereich != b.bereich)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  child: Text(b.bereich.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: BsFarben.textLeise)),
                ),
              _eintrag(b),
            ],
            if (andere.isNotEmpty)
              ExpansionTile(
                title: Text('Weitere Begriffe (${andere.length})', style: const TextStyle(fontSize: 13)),
                children: [for (final b in andere) _eintrag(b)],
              ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Tipp: In ein Eingabefeld klicken – die passende Erklärung erscheint oben.', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
            ),
          ]),
        ),
      ]),
    ),
    );
  }
}
