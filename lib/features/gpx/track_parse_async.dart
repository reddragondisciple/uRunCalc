/// Асинхронный разбор GPX: на нативных платформах — в фоновом изоляте,
/// на web — на главном потоке (изолятов там нет).
library;

import 'package:flutter/foundation.dart';

import 'track_parse.dart';

/// Тесты могут отключить изолят: результат приходит синхронно, без ожидания
/// сообщения из фонового порта. В приложении всегда `false`.
bool debugParseTrackSynchronously = false;

/// Запрос на разбор. Отдельный класс нужен, чтобы передать данные в изолят
/// одним сообщением.
class TrackParseRequest {
  const TrackParseRequest({
    required this.content,
    required this.withCandidates,
  });

  final String content;
  final bool withCandidates;
}

TrackParseResult _parseEntry(TrackParseRequest request) {
  return parseTrackContent(
    content: request.content,
    withCandidates: request.withCandidates,
  );
}

/// Разбирает GPX, не блокируя кадры интерфейса.
Future<TrackParseResult> parseTrackFileAsync(
  PickedTrackFile file, {
  bool withCandidates = true,
}) {
  if (kIsWeb || debugParseTrackSynchronously) {
    return Future.value(parseTrackFile(file, withCandidates: withCandidates));
  }
  return compute(
    _parseEntry,
    TrackParseRequest(content: file.content, withCandidates: withCandidates),
  );
}
