import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_run_calc/core/persisted_json_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('flush writes the latest snapshot with a schema version', () async {
    final store = PersistedJsonStore(
      storageKey: 'test_state',
      schemaVersion: 7,
      debounce: const Duration(milliseconds: 20),
    );

    store.schedule(() => {'value': 1});
    store.schedule(() => {'value': 2});
    await store.flush();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('test_state');
    expect(raw, isNotNull);

    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['version'], 7);
    expect(decoded['value'], 2);
  });

  test('load falls back to the legacy storage key', () async {
    SharedPreferences.setMockInitialValues({
      'legacy_state': jsonEncode({'value': 'old'}),
    });
    final store = PersistedJsonStore(
      storageKey: 'new_state',
      legacyStorageKey: 'legacy_state',
    );

    final data = await store.load();
    expect(data?['value'], 'old');
  });

  test('load ignores corrupted data', () async {
    SharedPreferences.setMockInitialValues({'broken_state': '{not json'});
    final store = PersistedJsonStore(storageKey: 'broken_state');

    expect(await store.load(), isNull);
  });

  test('debounce collapses rapid updates into one write', () async {
    var builds = 0;
    final store = PersistedJsonStore(
      storageKey: 'debounced_state',
      debounce: const Duration(milliseconds: 30),
    );

    for (var index = 0; index < 5; index++) {
      store.schedule(() {
        builds++;
        return {'value': index};
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 60));
    await store.flush();

    expect(builds, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('debounced_state'), contains('"value":4'));
  });
}
