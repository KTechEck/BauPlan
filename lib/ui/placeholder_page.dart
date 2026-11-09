import 'package:flutter/material.dart';

import '../app/theme.dart';

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.modul, required this.stufe});

  final String modul;
  final String stufe;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction_outlined, size: 48, color: BsFarben.textLeise),
          const SizedBox(height: 12),
          Text(modul, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Kommt in $stufe.', style: const TextStyle(color: BsFarben.textLeise)),
        ],
      ),
    );
  }
}
