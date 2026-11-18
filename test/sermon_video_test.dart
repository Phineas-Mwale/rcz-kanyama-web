import 'package:flutter_test/flutter_test.dart';
import 'package:rcz_kanyama/main.dart';

void main() {
  test('a live stream within the service window keeps its badge', () {
    final video = SermonVideo.fromJson({
      'video_id': 'live-1',
      'title': 'Sunday morning service',
      'is_live': true,
      'scheduled_start': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    });

    expect(video.isLive, isTrue);
  });

  test('an old live flag no longer shows a live badge', () {
    final video = SermonVideo.fromJson({
      'video_id': 'live-2',
      'title': 'Sunday morning service',
      'is_live': true,
      'scheduled_start': DateTime.now()
          .subtract(const Duration(hours: 13))
          .toUtc()
          .toIso8601String(),
    });

    expect(video.isLive, isFalse);
  });

  test(
    'publication dates and thumbnails survive the favourite list payload',
    () {
      final video = SermonVideo.fromJson({
        'id': 'dQw4w9WgXcQ',
        'title': 'A sermon',
        'published_at': '2026-01-04T09:00:00Z',
        'thumbnail_url': 'https://example.test/thumb.jpg',
        'created_at': '2026-02-01T09:00:00Z',
      });

      expect(video.id, 'dQw4w9WgXcQ');
      expect(video.publishedAt, isNotNull);
      expect(video.publishedAt!.toUtc().year, 2026);
      expect(video.thumbnail, 'https://example.test/thumb.jpg');
      expect(video.sortDate, video.publishedAt);
      expect(video.isLive, isFalse);
    },
  );
}
