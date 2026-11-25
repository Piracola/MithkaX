import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the topic tab strip sits for one chat.
///
/// exteraless keeps this per dialog (`topicssidetabsb<peer>` in the main
/// settings) and lets the reader move the tabs between the top of the
/// conversation and the bottom, above the composer. A wide shell still owns
/// its rail; this only drives the narrow strip.
enum TopicTabsPlacement { top, bottom }

/// Persists [TopicTabsPlacement] per account slot and chat.
class TopicTabsPlacementStore {
  TopicTabsPlacementStore._();

  static final TopicTabsPlacementStore shared = TopicTabsPlacementStore._();

  static const _prefix = 'mithka.topicTabsPlacement.v1';

  final Map<String, TopicTabsPlacement> _memory = {};

  String _key(int accountSlot, int chatId) => '$_prefix.$accountSlot.$chatId';

  /// The last known placement, without touching the disk. Defaults to [top].
  TopicTabsPlacement placementFor(int accountSlot, int chatId) =>
      _memory[_key(accountSlot, chatId)] ?? TopicTabsPlacement.top;

  Future<TopicTabsPlacement> load(int accountSlot, int chatId) async {
    final key = _key(accountSlot, chatId);
    final prefs = await SharedPreferences.getInstance();
    final placement = prefs.getString(key) == TopicTabsPlacement.bottom.name
        ? TopicTabsPlacement.bottom
        : TopicTabsPlacement.top;
    _memory[key] = placement;
    return placement;
  }

  Future<void> save(
    int accountSlot,
    int chatId,
    TopicTabsPlacement placement,
  ) async {
    final key = _key(accountSlot, chatId);
    _memory[key] = placement;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, placement.name);
  }

  @visibleForTesting
  void resetForTesting() => _memory.clear();
}
