import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Zeitlich sortierbare, auf jedem Gerät erzeugbare ID (UUID v7).
String neueId() => _uuid.v7();

/// Zeitstempel in UTC, ISO 8601.
String jetzt() => DateTime.now().toUtc().toIso8601String();
