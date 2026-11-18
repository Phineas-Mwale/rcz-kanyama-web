import 'package:flutter_test/flutter_test.dart';
import 'package:rcz_kanyama/features/congregation_history/domain/congregation_history_models.dart';

void main() {
  test('history entry maps years, people and media paths', () {
    final entry = CongregationHistoryEntry.fromJson(
      {
        'id': 'entry-1',
        'title': 'A shepherd for a new season',
        'category': 'Pastors',
        'person_name': 'Rev. Chanda',
        'position': 'Minister',
        'start_year': 1998,
        'end_year': 2005,
        'biography': 'A faithful ministry.',
        'cover_photo_path': 'user/entry/cover.jpg',
        'display_order': 2,
        'is_published': true,
      },
      photos: [
        const CongregationHistoryPhoto(
          id: 'photo-1',
          entryId: 'entry-1',
          storagePath: 'user/entry/one.jpg',
          caption: 'The induction service',
          displayOrder: 0,
        ),
      ],
    );

    expect(entry.yearsLabel, '1998 – 2005');
    expect(entry.peopleLine, 'Rev. Chanda • Minister');
    expect(entry.allPhotoPaths, ['user/entry/cover.jpg', 'user/entry/one.jpg']);
    expect(entry.isPublished, isTrue);
    expect(entry.photos.single.caption, 'The induction service');
  });

  test('open-ended years and missing people stay graceful', () {
    final entry = CongregationHistoryEntry.fromJson({
      'id': 'entry-2',
      'title': 'A continuing ministry',
      'category': 'Milestones',
      'start_year': 2012,
      'is_published': false,
    });

    expect(entry.yearsLabel, 'From 2012');
    expect(entry.peopleLine, isEmpty);
    expect(entry.coverPhotoPath, isNull);
    expect(entry.allPhotoPaths, isEmpty);
    expect(entry.isPublished, isFalse);
  });

  test('signed media urls attach without losing existing captions', () {
    final entry = CongregationHistoryEntry.fromJson(
      {
        'id': 'entry-3',
        'title': 'Archive record',
        'category': 'Events',
        'person_name': null,
        'cover_photo_path': 'user/entry/cover.jpg',
      },
      photos: [
        const CongregationHistoryPhoto(
          id: 'photo-2',
          entryId: 'entry-3',
          storagePath: 'user/entry/two.jpg',
          caption: 'Choir anniversary',
          displayOrder: 1,
        ),
      ],
    );

    final withMedia = entry.withMedia({
      'user/entry/cover.jpg': 'https://example.test/cover',
      'user/entry/two.jpg': 'https://example.test/two',
    });

    expect(withMedia.coverUrl, 'https://example.test/cover');
    expect(withMedia.photos.single.url, 'https://example.test/two');
    expect(withMedia.photos.single.caption, 'Choir anniversary');
  });
}
