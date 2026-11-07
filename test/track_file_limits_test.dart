import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/gpx_parser.dart';
import 'package:ultra_run_calc/features/gpx/track_store.dart';
import 'package:ultra_run_calc/features/pace/pace_gpx_import_ui.dart';

void main() {
  group('лимит размера файла трека', () {
    test('файл ровно на границе лимита допустим', () {
      expect(trackFileTooLargeError(gpxMaxBytes), isNull);
    });

    test('файл больше лимита отклоняется с понятным текстом', () {
      final error = trackFileTooLargeError(gpxMaxBytes + 1);
      expect(error, isNotNull);
      expect(error, contains('50 МБ'));
    });

    test('пустой и небольшой файл допустим', () {
      expect(trackFileTooLargeError(0), isNull);
      expect(trackFileTooLargeError(2048), isNull);
    });
  });

  group('DirectoryTrackFileStore читает только файлы в пределах лимита', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('uruncalc_track_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('файл в пределах лимита читается', () async {
      final store = DirectoryTrackFileStore(root, maxBytes: 64);
      await store.write(
        distanceKey: 'key',
        fileName: 'primary.gpx',
        content: 'короткий трек',
      );

      expect(
        await store.read(distanceKey: 'key', fileName: 'primary.gpx'),
        'короткий трек',
      );
    });

    test('слишком большой файл не читается и не попадает в память', () async {
      final store = DirectoryTrackFileStore(root, maxBytes: 4);
      await store.write(
        distanceKey: 'key',
        fileName: 'primary.gpx',
        content: '12345',
      );

      expect(
        await store.read(distanceKey: 'key', fileName: 'primary.gpx'),
        isNull,
      );
    });

    test('отсутствующий файл и удаление каталога не бросают', () async {
      final store = DirectoryTrackFileStore(root);
      expect(await store.read(distanceKey: 'none', fileName: 'x.gpx'), isNull);
      await store.deleteDistance('none');
    });
  });

  group('TrackFilePickException', () {
    test('сообщение пригодно для показа пользователю', () {
      const error = TrackFilePickException('Не удалось прочитать файл');
      expect(error.message, 'Не удалось прочитать файл');
      expect(error.toString(), 'Не удалось прочитать файл');
    });
  });
}
