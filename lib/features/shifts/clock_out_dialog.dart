import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/chs_colors.dart';

/// Confirms ending a shift and captures the canvasser's self-reported sign-up
/// count. Returns the entered non-negative integer on confirm, or `null` if the
/// canvasser cancels. A return value of `0` is a valid count (slow shift).
Future<int?> showClockOutSignupsDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _ClockOutSignupsDialog(),
  );
}

class _ClockOutSignupsDialog extends StatefulWidget {
  const _ClockOutSignupsDialog();

  @override
  State<_ClockOutSignupsDialog> createState() => _ClockOutSignupsDialogState();
}

class _ClockOutSignupsDialogState extends State<_ClockOutSignupsDialog> {
  final TextEditingController _ctrl = TextEditingController();
  int? _parsed;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  void _onChanged() {
    final text = _ctrl.text.trim();
    final value = int.tryParse(text);
    final next = (value != null && value >= 0) ? value : null;
    if (next != _parsed) setState(() => _parsed = next);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _parsed != null;
    return AlertDialog(
      title: const Text('End this shift?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your time will be saved. You can clock in again later.'),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Sign-ups this shift',
              hintText: 'e.g. 3',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kChsPrimary,
            foregroundColor: Colors.white,
          ),
          onPressed: valid ? () => Navigator.pop(context, _parsed) : null,
          child: const Text('Clock out'),
        ),
      ],
    );
  }
}
