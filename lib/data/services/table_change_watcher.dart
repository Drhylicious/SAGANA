import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Calls [onChange] when any row of the given tables is inserted, updated or
/// deleted, so a screen can reload quietly.
///
/// Stock is the reason it exists. A listing's quantity left changes the moment
/// an order is placed, cancelled or completed, often on someone else's phone.
/// Without this a screen kept showing the quantity it loaded with until the
/// person pulled down or reopened it, which is how a listing could read "20 kg"
/// long after 5 kg were ordered.
///
/// Events arrive in bursts (placing an order writes the order and the listing),
/// so they are collapsed into one [onChange] after [debounce]. Row Level
/// Security applies to realtime too: a Buyer only hears about rows they can
/// read.
///
/// Realtime is a convenience on top of the normal loads, never the only way a
/// screen gets its data. If the channel cannot be opened (offline, no
/// Supabase in a test) the watcher does nothing and the screen still reloads
/// on pull-to-refresh, on returning to the app and on coming back online.
class TableChangeWatcher {
  TableChangeWatcher({
    required this.tables,
    required this.onChange,
    this.debounce = const Duration(milliseconds: 500),
    this.client,
  });

  final List<String> tables;
  final void Function() onChange;
  final Duration debounce;

  /// Only set by tests; defaults to the app's Supabase client.
  final SupabaseClient? client;

  static int _next = 0;
  final int _id = _next++;
  final List<RealtimeChannel> _channels = [];
  Timer? _timer;
  bool _disposed = false;

  /// Opens one channel for all [tables]. Safe to call once.
  void start() {
    if (_disposed || _channels.isNotEmpty) return;
    try {
      final supabase = client ?? Supabase.instance.client;
      var channel = supabase.channel('watch_${_id}_${tables.join('_')}');
      for (final table in tables) {
        channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => notifyChanged(),
        );
      }
      channel.subscribe();
      _channels.add(channel);
    } catch (_) {
      // No realtime available: the screen's other refresh paths still work.
    }
  }

  /// Schedules [onChange]. Public so a burst can be simulated in tests.
  void notifyChanged() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (!_disposed) onChange();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final c in _channels) {
      c.unsubscribe();
    }
    _channels.clear();
  }
}
