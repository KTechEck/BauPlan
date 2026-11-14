import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../state/app_state.dart';
import 'hydraulik_schema_ansicht.dart';
import 'lueftung_ansicht.dart';
import 'regelung_ansicht.dart';
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.local_fire_department_outlined, size: 18), label: Text('Technikbereiche')),
                ButtonSegment(value: 1, icon: Icon(Icons.view_column_outlined, size: 18), label: Text('Schächte & Trassen')),
                ButtonSegment(value: 2, icon: Icon(Icons.account_tree_outlined, size: 18), label: Text('Hydraulikschema')),
                ButtonSegment(value: 3, icon: Icon(Icons.memory, size: 18), label: Text('Regelung (TA)')),
                ButtonSegment(value: 4, icon: Icon(Icons.air, size: 18), label: Text('Lüftung')),
                ButtonSegment(value: 5, icon: Icon(Icons.ac_unit, size: 18), label: Text('Kühlung & Klima')),
              ],
              selected: {_ansicht},
              onSelectionChanged: (v) => setState(() => _ansicht = v.first),
            ),
          ),
        ),
        Expanded(
          child: switch (_ansicht) {
            0 => TechnikraumAnsicht(state: widget.state),
            1 => SchachtAnsicht(state: widget.state),
            2 => HydraulikSchemaAnsicht(state: widget.state),
            3 => RegelungAnsicht(state: widget.state),
            4 => LueftungAnsicht(state: widget.state),
            _ => KlimaAnsicht(state: widget.state),
          },
        ),
      ]),
    );
  }
}
