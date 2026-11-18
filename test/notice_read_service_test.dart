import 'package:flutter_test/flutter_test.dart';
import 'package:rcz_kanyama/features/notices/notice_read_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read notices persist and reduce the unread count', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
    final preferences = await SharedPreferences.getInstance();
    final service = NoticeReadService(preferences);

    expect(service.unreadCount(['a', 'b', 'c']), 3);
    expect(await service.markRead('b'), isTrue);
    expect(service.isRead('b'), isTrue);
    expect(service.unreadCount(['a', 'b', 'c']), 2);

    // A fresh service must see the saved state after an app restart.
    final reopened = NoticeReadService(preferences);
    expect(reopened.isRead('b'), isTrue);
    expect(reopened.unreadCount(['a', 'b', 'c']), 2);
  });

  test('reading the same notice twice stays idempotent', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final service = NoticeReadService(preferences);

    expect(await service.markRead('notice-1'), isTrue);
    expect(await service.markRead('notice-1'), isTrue);
    expect(service.unreadCount(['notice-1']), 0);
  });

  test('a missing notice id is never treated as read', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final service = NoticeReadService(preferences);

    expect(service.isRead(null), isFalse);
    expect(await service.markRead(null), isFalse);
    expect(service.unreadCount([null]), 0);
  });
}
