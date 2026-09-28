import 'package:flutter_test/flutter_test.dart';
import 'package:chs_companion/features/stats/manager/summary_export.dart';

void main() {
  final totals = <String, dynamic>{
    'knocks': 100,
    'answers': 40,
    'signups': 8,
    'shift_signups': 2,
    'answer_rate': .4,
    'knocks_per_hour': 25,
    'answers_per_hour': 10,
    'shift_hours': 2,
    'knock_hours': 4,
    'total_hours': 6,
    'overlap_count': 1,
  };
  test('exports summary calculations, filters and overlap warning', () {
    final rows = summaryExportRows(
      totals: totals,
      conversionRate: 50,
      zipFiltered: false,
      filters: {'Start date': '2026-09-01'},
    );
    final values = {for (final row in rows) row[0]: row[1]};
    expect(values['Start date'], '2026-09-01');
    expect(values['Signup Rate'], '20.0%');
    expect(values['Converted Audits'], '5.0');
    expect(values['Total Cost'], '300.00');
    expect(values['Cost Per Audit'], '60.00');
    expect(values['Total Hours'], '6.00');
    expect(values['Hours note'], contains('double count'));
    expect(
      values.keys,
      containsAll([
        'Knocks',
        'Answers',
        'Signups',
        'Shift signups',
        'Answer Rate',
        'Knocks/Hour',
        'Answers/Hour',
        'Shift Hours',
        'Knock Hours',
        'Conversion Rate',
      ]),
    );
  });
  test('empty and ZIP-filtered summary handles unavailable values', () {
    final rows = summaryExportRows(
      totals: {},
      conversionRate: 0,
      zipFiltered: true,
      filters: {},
    );
    final values = {for (final row in rows) row[0]: row[1]};
    expect(values.containsKey('Shift Hours'), false);
    expect(values.containsKey('Shift signups'), false);
    expect(values['Cost Per Audit'], '—');
    expect(values['Signup Rate'], '—');
    expect(values['Total Cost'], '0.00');
  });
  test('CSV escapes quotes, commas, newlines and formula-like text', () {
    expect(
      encodeSpreadsheet([
        ['a,"b"\nc', '=SUM(A1)'],
      ]),
      '"a,""b""\nc","\'=SUM(A1)"',
    );
  });
  test(
    'Sheets uses tab-separated cells and removes embedded tabs and newlines',
    () {
      expect(
        encodeSpreadsheet([
          ['ZIP codes', '01234'],
          ['Notes', 'a\tb\nc'],
        ], separator: '\t'),
        'ZIP codes\t01234\r\nNotes\ta b c',
      );
    },
  );
}
