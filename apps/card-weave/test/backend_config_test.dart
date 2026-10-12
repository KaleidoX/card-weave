import 'package:flutter_test/flutter_test.dart';
import 'package:card_weave/model.dart';

void main() {
  test('Legacy Nutstore directory retains the same remote location', () {
    final config = publicBackend({
      'type': 'webdav',
      'endpoint': 'https://dav.jianguoyun.com/dav/card-weave',
      'credential_ref': 'not-exported',
    });
    expect(config, {
      'type': 'webdav',
      'endpoint': 'https://dav.jianguoyun.com/dav/',
      'directory': 'card-weave',
    });
    validateBackend(config);
    expect(publicBackend(config), config);
  });
  test(
    'Explicit service and directory survive sharing without credentials',
    () {
      final config = publicBackend({
        'type': 'webdav',
        'endpoint': 'https://example.invalid/service/',
        'directory': 'Contacts/Family',
        'password': 'fixture-only',
      });
      expect(config['directory'], 'Contacts/Family');
      expect(config.containsKey('password'), isFalse);
      validateBackend(config);
      for (final path in ['../escape', 'a/../b', 'a//b', 'a\\b', 'a\u0000b']) {
        expect(
          () => validateBackend({...config, 'directory': path}),
          throwsA(isA<AppFailure>()),
        );
      }
    },
  );
  test(
    'Unknown legacy endpoints are preserved instead of guessing service roots',
    () {
      expect(
        publicBackend({
          'type': 'webdav',
          'endpoint': 'https://example.invalid/service/book',
        })['endpoint'],
        'https://example.invalid/service/book',
      );
      expect(
        publicBackend({
          'type': 'webdav',
          'endpoint': 'https://example.invalid/service/book',
        })['directory'],
        '',
      );
    },
  );
}
