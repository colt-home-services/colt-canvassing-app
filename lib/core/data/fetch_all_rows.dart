import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads every row even when the server caps pages below [pageSize].
/// Callers must supply a fresh query with stable, unique ordering and exact count.
Future<List<Map<String, dynamic>>> fetchAllRows(
  Future<PostgrestResponse<List<Map<String, dynamic>>>> Function(
    int from,
    int to,
  )
  fetchPage, {
  int pageSize = 500,
}) async {
  if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
  final rows = <Map<String, dynamic>>[];
  int? expectedCount;
  while (true) {
    final page = await fetchPage(rows.length, rows.length + pageSize - 1);
    expectedCount ??= page.count;
    if (page.count != expectedCount) {
      throw StateError('Database rows changed while loading. Please retry.');
    }
    rows.addAll(page.data);
    if (rows.length == expectedCount) return rows;
    if (page.data.isEmpty || rows.length > expectedCount) {
      throw StateError('Incomplete database result. Please retry.');
    }
  }
}
