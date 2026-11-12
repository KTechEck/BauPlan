import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app/qr_bild.dart';

/// Kopplungs-QR-Code vom PC (Einstellungen › Speicher und Abgleich) scannen.
/// Liefert Adressen, Code und PC-Namen.
class QrScannenSeite extends StatefulWidget {
  const QrScannenSeite({super.key});

  @override
  State<QrScannenSeite> createState() => _QrScannenSeiteState();
}

class _QrScannenSeiteState extends State<QrScannenSeite> {
  bool _fertig = false;
  String? _fremd;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('QR-Code vom PC scannen')),
        body: Stack(children: [
          MobileScanner(
            onDetect: (erfasst) {
              if (_fertig) return;
              for (final c in erfasst.barcodes) {
                final k = c.rawValue == null ? null : kopplungLesen(c.rawValue!);
                if (k != null) {
                  _fertig = true;
                  Navigator.pop(context, k);
                  return;
                }
                if (c.rawValue != null) setState(() => _fremd = c.rawValue);
              }
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Text(
                _fremd == null
                    ? 'Am PC: BauSpur › Einstellungen › Speicher und Abgleich. Den QR-Code neben dem Kopplungscode ins Bild halten.'
                    : 'Das ist kein BauSpur-Kopplungscode.',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ]),
      );
}
