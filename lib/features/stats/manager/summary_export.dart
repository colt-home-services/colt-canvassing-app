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
