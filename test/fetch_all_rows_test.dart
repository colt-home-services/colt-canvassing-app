import 'package:chs_companion/core/data/fetch_all_rows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'reads every page even when server cap is below requested size',
    () async {
      final starts = <int>[];
      final rows = await fetchAllRows((from, to) async {
        starts.add(from);
        return PostgrestResponse(
          data: [
            for (var i = from; i < from + 2 && i < 5; i++) {'id': i},
          ],
          count: 5,
        );
      });
      expect(rows.map((row) => row['id']), [0, 1, 2, 3, 4]);
      expect(starts, [0, 2, 4]);
    },
  );
  test('empty results do not require an out-of-range request', () async {
    expect(
      await fetchAllRows((_, _) async => PostgrestResponse(data: [], count: 0)),
      isEmpty,
    );
  });
  test('refuses a partial result when the database count changes', () async {
    await expectLater(
      fetchAllRows(
        (from, to) async => PostgrestResponse(
          data: [
            {'id': from},
          ],
          count: from == 0 ? 3 : 4,
        ),
      ),
      throwsStateError,
    );
  });
  test('refuses incomplete pages', () async {
    await expectLater(
      fetchAllRows((_, _) async => PostgrestResponse(data: [], count: 4)),
      throwsStateError,
    );
  });
  test('query failures propagate instead of exporting partial data', () async {
    await expectLater(
      fetchAllRows((from, to) async {
        if (from > 0) throw StateError('Database unavailable');
        return PostgrestResponse(
          data: [
            {'id': 1},
          ],
          count: 2,
        );
      }),
      throwsStateError,
    );
  });
}
