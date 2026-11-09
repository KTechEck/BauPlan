import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../state/app_state.dart';
import 'schacht_ansicht.dart';
import 'technikraum_ansicht.dart';

/// Modul Haustechnik: Technik-/Heizraumplaner und Schacht-/Trassenplaner.
class HaustechnikPage extends StatefulWidget {
  const HaustechnikPage({super.key, required this.state});
  final AppState state;

  @override
  State<HaustechnikPage> createState() => _HaustechnikPageState();
}

class _HaustechnikPageState extends State<HaustechnikPage> {
  int _ansicht = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
          child: Row(children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.local_fire_department_outlined, size: 18), label: Text('Technikraum')),
                ButtonSegment(value: 1, icon: Icon(Icons.view_column_outlined, size: 18), label: Text('Schächte & Trassen')),
              ],
              selected: {_ansicht},
              onSelectionChanged: (v) => setState(() => _ansicht = v.first),
            ),
          ]),
        ),
        Expanded(child: _ansicht == 0 ? TechnikraumAnsicht(state: widget.state) : SchachtAnsicht(state: widget.state)),
      ]),
    );
  }
}
