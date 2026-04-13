import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/chs_colors.dart';
import 'shift_service.dart';

class ClockCard extends StatefulWidget {
  const ClockCard({super.key, this.compact = false});

  /// Compact mode: a slimmer single-row layout suited for pages that already
  /// have their own primary content (e.g. mounted at the top of TownsPage).
  final bool compact;

  @override
  State<ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<ClockCard> {
  final ShiftService _svc = ShiftService(Supabase.instance.client);

  Shift? _active;
  List<Shift> _today = const [];
  bool _loading = true;
  bool _busy = false;
  bool _hidden = false;
  bool _roleChecked = false;

  Timer? _tick;
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid != null) {
      try {
        final row = await client
            .from('profiles')
            .select('role')
            .match({'user_id': uid})
            .maybeSingle();
        final role = (row?['role'] ?? '').toString();
        if (role == 'manager') {
          if (mounted) setState(() {
            _hidden = true;
            _roleChecked = true;
          });
          return;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _roleChecked = true);
    _refresh();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _updateElapsed());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  void _updateElapsed() {
    final a = _active;
    if (a == null) {
      if (_elapsed.value != Duration.zero) _elapsed.value = Duration.zero;
      return;
    }
    _elapsed.value = DateTime.now().difference(a.clockInAt);
  }

  Future<void> _refresh() async {
    try {
      final active = await _svc.activeShift();
      final today = await _svc.todayShifts();
      if (!mounted) return;
      setState(() {
        _active = active;
        _today = today;
        _loading = false;
      });
      _updateElapsed();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Could not load shift: $e');
    }
  }

  Future<(double?, double?, double?)> _getLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return (null, null, null);
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return (pos.latitude, pos.longitude, pos.accuracy);
    } catch (_) {
      return (null, null, null);
    }
  }

  Future<void> _onClockIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final (lat, lon, acc) = await _getLocation();
      await _svc.clockIn(lat: lat, lon: lon, accuracyM: acc);
      await _refresh();
    } catch (e) {
      _showError('Clock-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onClockOut() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End this shift?'),
        content: const Text('Your time will be saved. You can clock in again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kChsPrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clock out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final (lat, lon, acc) = await _getLocation();
      await _svc.clockOut(lat: lat, lon: lon, accuracyM: acc);
      await _refresh();
    } catch (e) {
      _showError('Clock-out failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '${h.toString().padLeft(2, '0')}:$mm:$ss';
  }

  String _fmtTotal(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final hour12 = ((local.hour + 11) % 12) + 1;
    final am = local.hour < 12 ? 'AM' : 'PM';
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hour12:$mm $am';
  }

  @override
  Widget build(BuildContext context) {
    if (!_roleChecked || _hidden) return const SizedBox.shrink();
    if (_loading) {
      return _cardShell(
        child: const SizedBox(
          height: 56,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: kChsPrimary,
              ),
            ),
          ),
        ),
      );
    }

    final active = _active;
    final isClockedIn = active != null;

    final todayTotal = _today.fold<Duration>(
      Duration.zero,
      (sum, s) => sum + s.duration,
    );
    final shiftCount = _today.length;

    return _cardShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _statusDot(isClockedIn),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      isClockedIn ? 'On the clock' : 'Off the clock',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kChsTextSecondary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (isClockedIn) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· since ${_fmtTime(active.clockInAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: kChsTextSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (isClockedIn)
                  ValueListenableBuilder<Duration>(
                    valueListenable: _elapsed,
                    builder: (_, d, __) => Text(
                      _fmtDuration(d),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: kChsTextPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                        height: 1.1,
                      ),
                    ),
                  )
                else
                  Text(
                    shiftCount == 0
                        ? 'Tap to start your shift'
                        : 'Today: ${_fmtTotal(todayTotal)} · $shiftCount shift${shiftCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kChsTextPrimary,
                    ),
                  ),
                if (isClockedIn && shiftCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Today: ${_fmtTotal(todayTotal)} · $shiftCount shift${shiftCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: kChsTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _actionButton(isClockedIn),
        ],
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: kChsCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E8EE), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: child,
    );
  }

  Widget _statusDot(bool on) {
    final color = on ? const Color(0xFF22C55E) : const Color(0xFFCBD5E1);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: on
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  Widget _actionButton(bool isClockedIn) {
    final bg = isClockedIn ? kChsCard : kChsPrimary;
    final fg = isClockedIn ? kChsPrimary : Colors.white;
    final border = isClockedIn
        ? const BorderSide(color: kChsPrimary, width: 1.5)
        : BorderSide.none;

    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed:
            _busy ? null : (isClockedIn ? _onClockOut : _onClockIn),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          side: border,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        child: _busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg,
                ),
              )
            : Text(isClockedIn ? 'Clock out' : 'Clock in'),
      ),
    );
  }
}
