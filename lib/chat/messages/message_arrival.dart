//
//  message_arrival.dart
//
//  The entrance a message plays when it lands in an open transcript. A new
//  bubble used to pop into place with no transition; it now rises into
//  position while fading in, so an arriving message reads as content settling
//  rather than the list cutting to a new frame.
//
//  Layout never moves: the wrapper paints its child at its final size from the
//  first frame, and only the paint transform and opacity animate. Rows that
//  were already on screen (scroll rebinds, read receipts, edits) open at their
//  resting state, which is what [animate] false is for.
//

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class MessageArrival extends StatefulWidget {
  const MessageArrival({
    super.key,
    required this.animate,
    required this.outgoing,
    required this.child,
  });

  /// Whether this row is a live arrival. It is read once, when the row's State
  /// is created: later rebuilds of the same row (a sender resolving, a read
  /// receipt, an edit) pass whatever the id set says now and must neither
  /// restart nor cancel an entrance already in flight.
  final bool animate;

  /// Outgoing bubbles grow out of their bottom-right corner; incoming ones
  /// out of their bottom-left, the corner they entered from.
  final bool outgoing;

  final Widget child;

  /// The app's `deliberate` beat: long enough to read as a settle, short
  /// enough that a burst of messages never queues up behind it.
  static const Duration duration = AppMotion.deliberate;

  /// How far below its resting place the bubble starts, in logical pixels.
  static const double rise = 8;

  /// The bubble starts a hair small so the eye reads it as arriving, not as
  /// a resized row.
  static const double startScale = 0.94;

  @override
  State<MessageArrival> createState() => _MessageArrivalState();
}

class _MessageArrivalState extends State<MessageArrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MessageArrival.duration,
  );
  late final CurvedAnimation _settle = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.standard,
  );
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.6, curve: Curves.easeOut),
  );

  /// True once the entrance is over; the wrappers are dropped then, so a
  /// resting row paints through no save layer and no transform.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_handleStatus);
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1;
      _settled = true;
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _settled || !mounted) return;
    setState(() => _settled = true);
  }

  @override
  void dispose() {
    _settle.dispose();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_settled) return widget.child;
    final alignment = widget.outgoing
        ? Alignment.bottomRight
        : Alignment.bottomLeft;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final settle = _settle.value;
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, MessageArrival.rise * (1 - settle)),
            child: Transform.scale(
              scale:
                  MessageArrival.startScale +
                  (1 - MessageArrival.startScale) * settle,
              alignment: alignment,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
