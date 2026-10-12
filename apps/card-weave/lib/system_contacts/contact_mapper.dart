import 'dart:async';

import 'event_dates.dart';
import 'mapping.dart';

/// Converts the entire source contact, including cross-field vendor metadata.
abstract interface class SystemContactMapper {
  /// Opt in to textual vendor rows; unclaimed extension payloads stay on-device.
  Set<String> get additionalMimeTypes;
  Future<ImportCandidate> mapContact(
    Map<String, dynamic> summary,
    Map<String, dynamic> detail,
  );
}

class AndroidContactMapper implements SystemContactMapper {
  const AndroidContactMapper();
  @override
  Set<String> get additionalMimeTypes => const {};

  FutureOr<Map<String, dynamic>?> decodeEventDate(Map<String, dynamic> row) =>
      decodeAndroidEventDate(row);

  @override
  Future<ImportCandidate> mapContact(
    Map<String, dynamic> summary,
    Map<String, dynamic> detail,
  ) => mapSystemContact(summary, detail, decodeEventDate: decodeEventDate);
}
