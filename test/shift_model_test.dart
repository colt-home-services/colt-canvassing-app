import 'package:flutter_test/flutter_test.dart';
import 'package:chs_companion/features/shifts/shift_service.dart';

void main() {
  group('Shift.fromMap self_reported_signups', () {
    test('parses an integer count', () {
      final s = Shift.fromMap({
        'id': 'a',
        'user_id': 'u',
        'clock_in_at': '2026-06-03T12:00:00Z',
        'clock_out_at': '2026-06-03T16:00:00Z',
        'self_reported_signups': 3,
      });
      expect(s.selfReportedSignups, 3);
    });

    test('is null when absent', () {
      final s = Shift.fromMap({
        'id': 'a',
        'user_id': 'u',
        'clock_in_at': '2026-06-03T12:00:00Z',
        'clock_out_at': null,
      });
      expect(s.selfReportedSignups, isNull);
    });

    test('keeps an explicit zero (not coerced to null)', () {
      final s = Shift.fromMap({
        'id': 'a',
        'user_id': 'u',
        'clock_in_at': '2026-06-03T12:00:00Z',
        'clock_out_at': '2026-06-03T16:00:00Z',
        'self_reported_signups': 0,
      });
      expect(s.selfReportedSignups, 0);
    });
  });
}
