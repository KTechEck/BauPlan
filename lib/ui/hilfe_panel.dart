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

  final _sucheFokus = FocusNode();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_fokus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_fokus);
    _suche.dispose();
    _sucheFokus.dispose();
    super.dispose();
  }

  /// Gewähltes Feld erkennen: Beschriftung des Eingabefelds/der Auswahlliste.
  void _fokus() {
    final f = FocusManager.instance.primaryFocus;
    if (f == null || f == _sucheFokus) return;
    final ctx = f.context;
    if (ctx == null || !ctx.mounted) return;
    final d = ctx.findAncestorWidgetOfExactType<InputDecorator>()?.decoration ?? ctx.findAncestorWidgetOfExactType<TextField>()?.decoration;
    final text = d?.labelText ?? d?.hintText ?? d?.helperText;
    if (text == null || text == _feldText) return;
    if (!mounted) return;
    setState(() {
      _feldText = text;
      _feld = begriffZuFeld(text);
    });
  }

  Widget _erklaerung(Begriff b) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 2),
        Text(b.bereich, style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
        const SizedBox(height: 10),
        Text(b.kurz, style: const TextStyle(fontSize: 13, height: 1.4)),
        if (b.einheit.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Einheit: ', style: TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: b.einheit),
          ]), style: const TextStyle(fontSize: 13)),
        ],
        if (b.eingabe.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Was eingeben: ', style: TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: b.eingabe),
          ]), style: const TextStyle(fontSize: 13)),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final q = _suche.text.trim();
    final treffer = q.isEmpty ? const <Begriff>[] : glossar.where((b) => b.passt(q)).take(8).toList();
    final f = _feld;
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
              const Expanded(child: Text('Hilfe zum Feld', style: TextStyle(fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Hilfe ausblenden', icon: const Icon(Icons.close, size: 18), onPressed: () => hilfePanelUmschalten(widget.state)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 12), children: [
              if (_feldText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Feld: „$_feldText“', style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
                ),
              if (f != null)
                _erklaerung(f)
              else
                Text(
                  _feldText == null
                      ? 'In ein Eingabefeld klicken – hier erscheint dann, was der Wert bedeutet, in welcher Einheit er steht und was man eingibt.'
                      : 'Zu diesem Feld gibt es noch keine Erklärung. Unten kannst du einen Begriff nachschlagen.',
                  style: const TextStyle(color: BsFarben.textLeise, height: 1.4),
                ),
              const Divider(height: 28),
              TextField(
                controller: _suche,
                focusNode: _sucheFokus,
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Begriff nachschlagen, z. B. kv, Uw'),
                onChanged: (_) => setState(() {}),
              ),
              for (final b in treffer)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(b.name),
                  subtitle: Text(b.bereich, style: const TextStyle(fontSize: 11)),
                  onTap: () => setState(() {
                    _feld = b;
                    _feldText = null;
                    _suche.clear();
                  }),
                ),
              if (q.isNotEmpty && treffer.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nichts gefunden.')),
            ]),
          ),
        ]),
      ),
    );
  }
}
