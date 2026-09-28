List<List<String>> summaryExportRows({
  required Map<String, dynamic> totals,
  required double conversionRate,
  required bool zipFiltered,
  required Map<String, String> filters,
}) {
  num value(String key) => num.tryParse('${totals[key]}') ?? 0;
  String fixed(String key, int digits) => value(key).toStringAsFixed(digits);
  final audits =
      (value('signups') + value('shift_signups')) * conversionRate / 100;
  final cost = value('total_hours') * 25 + audits * 30;
  return [
    ['Field', 'Value'],
    for (final filter in filters.entries) [filter.key, filter.value],
    ['Knocks', fixed('knocks', 0)],
    ['Answers', fixed('answers', 0)],
    ['Signups', fixed('signups', 0)],
    if (!zipFiltered) ['Shift signups', fixed('shift_signups', 0)],
    [
      'Signup Rate',
      value('answers') > 0
          ? '${(value('signups') / value('answers') * 100).toStringAsFixed(1)}%'
          : '—',
    ],
    ['Answer Rate', '${(value('answer_rate') * 100).toStringAsFixed(1)}%'],
    ['Knocks/Hour', fixed('knocks_per_hour', 1)],
    ['Answers/Hour', fixed('answers_per_hour', 1)],
    if (!zipFiltered) ['Shift Hours', fixed('shift_hours', 2)],
    ['Knock Hours', fixed('knock_hours', 2)],
    ['Total Hours', fixed('total_hours', 2)],
    ['Conversion Rate', '$conversionRate%'],
    ['Converted Audits', audits.toStringAsFixed(1)],
    ['Total Cost', cost.toStringAsFixed(2)],
    ['Cost Per Audit', audits > 0 ? (cost / audits).toStringAsFixed(2) : '—'],
    ['Overlap days', fixed('overlap_count', 0)],
    if (value('overlap_count') > 0)
      [
        'Hours note',
        'Shift and knock time overlap. Total Hours may double count time.',
      ],
    ['Cost calculation', 'Total Hours × 25 + Converted Audits × 30'],
    [
      'Estimate note',
      'Conversion Rate is entered locally. Converted Audits, Total Cost and Cost Per Audit are estimates, not recorded audits or payroll payments. Open shift hours can change until clock-out.',
    ],
  ];
}

String encodeSpreadsheet(List<List<String>> rows, {String separator = ','}) {
  String cell(String value) {
    // Keep user-entered labels from becoming spreadsheet formulas.
    if (RegExp(r'^\s*[=+@-]').hasMatch(value)) value = "'$value";
    if (separator == '\t') return value.replaceAll(RegExp(r'[\t\r\n]'), ' ');
    return '"${value.replaceAll('"', '""')}"';
  }

  return rows.map((row) => row.map(cell).join(separator)).join('\r\n');
}

/// Builds one payroll summary row per person with positive hours in the period.
/// [dailyRows] must already have the selected date and ZIP filters applied.
List<List<String>> canvasserPayrollRows({
  required List<Map<String, dynamic>> dailyRows,
  required List<Map<String, dynamic>> shiftRows,
  required Set<String> knockDateKeys,
  required double conversionRate,
  required DateRangeStrings range,
  required bool zipFiltered,
}) {
  num number(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
  String userDateKey(Map<String, dynamic> row) =>
      '${row['user_id'] ?? ''}|${row['work_date_ny'] ?? ''}';
  final people = <String, Map<String, dynamic>>{};
  Map<String, dynamic> person(String email) => people.putIfAbsent(
    email,
    () => {
      'email': email,
      'knocks': 0,
      'answers': 0,
      'signups': 0,
      'knock_hours': 0,
      'shift_seconds': 0,
      'shift_signups': 0,
      'shift_dates': <String>{},
    },
  );
  for (final row in dailyRows) {
    final email = '${row['user_email'] ?? ''}'.trim();
    if (email.isEmpty) continue;
    final p = person(email);
    p['knocks'] = number(p['knocks']) + number(row['total_knocks']);
    p['answers'] = number(p['answers']) + number(row['answers']);
    p['signups'] = number(p['signups']) + number(row['signed_ups']);
    p['knock_hours'] = number(p['knock_hours']) + number(row['billable_hours']);
  }
  if (!zipFiltered) {
    for (final row in shiftRows) {
      final email = '${row['user_email'] ?? ''}'.trim();
      if (email.isEmpty) continue;
      final p = person(email);
      p['shift_seconds'] =
          number(p['shift_seconds']) + number(row['duration_seconds']);
      p['shift_signups'] =
          number(p['shift_signups']) + number(row['self_reported_signups']);
      if (number(row['duration_seconds']) > 0 && row['is_bonus'] != true) {
        (p['shift_dates'] as Set<String>).add(userDateKey(row));
      }
    }
  }

  final output = <List<String>>[
    [
      'Start date',
      'End date',
      'Canvasser',
      'Total Cost',
      'Knocks',
      'Answers',
      'Signups',
      if (!zipFiltered) 'Shift signups',
      'Signup Rate',
      'Answer Rate',
      'Knocks/Hour',
      'Answers/Hour',
      if (!zipFiltered) 'Shift Hours',
      'Knock Hours',
      'Total Hours',
      'Overlap days',
      'Conversion Rate',
      'Converted Audits',
      'Cost Per Audit',
    ],
  ];
  final emails = people.keys.toList()..sort();
  for (final email in emails) {
    final p = people[email]!;
    final knockHours = number(p['knock_hours']);
    final shiftHours = number(p['shift_seconds']) / 3600;
    final totalHours = knockHours + shiftHours;
    if (totalHours <= 0) continue;
    final shiftDates = p['shift_dates'] as Set<String>;
    final overlap = zipFiltered
        ? 0
        : shiftDates.where(knockDateKeys.contains).length;
    final answers = number(p['answers']);
    final signups = number(p['signups']);
    final shiftSignups = number(p['shift_signups']);
    final totals = <String, dynamic>{
      'knocks': number(p['knocks']),
      'answers': answers,
      'signups': signups,
      'shift_signups': shiftSignups,
      'knock_hours': knockHours,
      'shift_hours': shiftHours,
      'total_hours': totalHours,
      'overlap_count': overlap,
      'answer_rate': number(p['knocks']) > 0
          ? answers / number(p['knocks'])
          : 0,
      'knocks_per_hour': knockHours > 0 ? number(p['knocks']) / knockHours : 0,
      'answers_per_hour': knockHours > 0 ? answers / knockHours : 0,
    };
    final summary = summaryExportRows(
      totals: totals,
      conversionRate: conversionRate,
      zipFiltered: zipFiltered,
      filters: const {},
    );
    final values = {for (final row in summary.skip(1)) row[0]: row[1]};
    output.add([
      range.start,
      range.end,
      email,
      values['Total Cost']!,
      values['Knocks']!,
      values['Answers']!,
      values['Signups']!,
      if (!zipFiltered) values['Shift signups']!,
      values['Signup Rate']!,
      values['Answer Rate']!,
      values['Knocks/Hour']!,
      values['Answers/Hour']!,
      if (!zipFiltered) values['Shift Hours']!,
      values['Knock Hours']!,
      values['Total Hours']!,
      values['Overlap days']!,
      values['Conversion Rate']!,
      values['Converted Audits']!,
      values['Cost Per Audit']!,
    ]);
  }
  return output;
}

class DateRangeStrings {
  const DateRangeStrings({required this.start, required this.end});
  final String start;
  final String end;
}
