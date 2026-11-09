import 'package:flutter/material.dart';

/// Ein Symbol je Funktion – überall im Programm dasselbe.
class Sym {
  // Werkzeuge
  static const auswahl = Icons.near_me_outlined;
  static const wand = Icons.view_week_outlined;
  static const rechteck = Icons.crop_square;
  static const raum = Icons.meeting_room_outlined;
  static const oeffnung = Icons.door_front_door_outlined;
  static const bemassen = Icons.straighten;
  static const winkel = Icons.architecture;
  static const setzen = Icons.add_location_alt_outlined;
  static const planvorlage = Icons.image_outlined;
  static const kalibrieren = Icons.square_foot;

  // Aktionen
  static const loeschen = Icons.delete_outline;
  static const rueckgaengig = Icons.undo;
  static const allesZeigen = Icons.fit_screen_outlined;
  static const bearbeiten = Icons.edit_outlined;
  static const hinzufuegen = Icons.add;
  static const sperren = Icons.lock_outline;
  static const entsperren = Icons.lock_open_outlined;
  static const ausblenden = Icons.visibility_off_outlined;
  static const einblenden = Icons.visibility_outlined;
  static const umdrehen = Icons.swap_horiz;
  static const importieren = Icons.add_photo_alternate_outlined;
  static const ordner = Icons.folder_open_outlined;
  static const pdf = Icons.picture_as_pdf_outlined;
  static const aktualisieren = Icons.sync;
  static const hilfe = Icons.keyboard_outlined;
  static const verorten = Icons.place_outlined;
  static const richtung = Icons.explore_outlined;
  static const leitung = Icons.polyline_outlined;
  static const parallel = Icons.dehaze;
  static const verlaengern = Icons.trending_flat;
  static const decke = Icons.light_outlined;
  static const heizkreisverteiler = Icons.tune;

  // Module
  static const projekt = Icons.folder_outlined;
  static const grundriss = Icons.grid_view_outlined;
  static const installation = Icons.cable_outlined;
  static const haustechnik = Icons.local_fire_department_outlined;
  static const verteiler = Icons.electrical_services_outlined;
  static const assistent = Icons.auto_awesome_outlined;
  static const fotos = Icons.photo_camera_outlined;
  static const kosten = Icons.euro_outlined;
  static const tagebuch = Icons.menu_book_outlined;
  static const export = Icons.ios_share_outlined;
  static const einstellungen = Icons.settings_outlined;
  static const bauteile = Icons.window_outlined;
  static const bauphysik = Icons.thermostat_outlined;
}

/// Werkzeugknopf mit Symbol und kurzem Text darunter – einheitlich in allen Modulen.
class WerkzeugKnopf extends StatelessWidget {
  const WerkzeugKnopf({
    super.key,
    required this.symbol,
    required this.text,
    required this.aktiv,
    required this.onTap,
    this.tooltip,
  });

  final IconData symbol;
  final String text;
  final bool aktiv;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final knopf = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 52),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: aktiv ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: aktiv ? Border.all(color: const Color(0xFFC8CBC4)) : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(symbol, size: 20, color: aktiv ? const Color(0xFF9A3412) : const Color(0xFF1C2024)),
          const SizedBox(height: 2),
          Text(text, style: TextStyle(fontSize: 10.5, fontWeight: aktiv ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
    return tooltip == null ? knopf : Tooltip(message: tooltip!, child: knopf);
  }
}

/// Hintergrund einer Werkzeuggruppe.
class WerkzeugGruppe extends StatelessWidget {
  const WerkzeugGruppe({super.key, required this.kinder});
  final List<Widget> kinder;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: const Color(0xFFF0F1ED), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: kinder),
      );
}
