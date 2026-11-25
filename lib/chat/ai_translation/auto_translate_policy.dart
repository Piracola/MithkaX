import '../../settings/translation_controller.dart';
import '../../tdlib/td_models.dart';

String automaticTranslationSourceText(ChatMessage message) {
  if (!_hasTranslatableText(message)) return '';
  final parts = [
    message.text,
    message.linkPreview?.title ?? '',
    message.linkPreview?.description ?? '',
  ].where((part) => part.trim().isNotEmpty);
  return parts.join('\n');
}

/// A Gram transfer's text is its preview line ("[Transfer] 1.5 GRAM"), not
/// anything its sender wrote, so it is never translated or sampled.
bool _hasTranslatableText(ChatMessage message) => message.gramTransfer == null;

const _languageDetectionIgnoredEntityTypes = <String>{
  'textEntityTypePre',
  'textEntityTypePreCode',
  'textEntityTypeCode',
  'textEntityTypeUrl',
  'textEntityTypeEmailAddress',
  'textEntityTypeMention',
  'textEntityTypeHashtag',
  'textEntityTypeBotCommand',
};

String automaticTranslationLanguageText(ChatMessage message) {
  if (!_hasTranslatableText(message)) return '';
  var text = message.text.length > 256
      ? message.text.substring(0, 256)
      : message.text;
  final ranges =
      message.textEntities
          .where(
            (entity) =>
                _languageDetectionIgnoredEntityTypes.contains(entity.type) &&
                entity.offset >= 0 &&
                entity.offset < text.length,
          )
          .map(
            (entity) => (
              start: entity.offset,
              end: entity.end.clamp(entity.offset, text.length),
            ),
          )
          .where((range) => range.end > range.start)
          .toList()
        ..sort((a, b) => b.start.compareTo(a.start));
  for (final range in ranges) {
    text = text.replaceRange(range.start, range.end, '');
  }
  return text.trim();
}

List<ChatMessage> automaticTranslationCandidates(
  List<ChatMessage> messages, {
  required String targetLanguageCode,
  Set<int> excludedMessageIds = const {},
  Set<int> visibleMessageIds = const {},
  int limit = 12,
}) {
  final target = TranslationController.normalizeLanguageCode(
    targetLanguageCode,
  );
  final onScreen = <ChatMessage>[];
  final rest = <ChatMessage>[];
  // The walk is not truncated at [limit]: a message inside the viewport may
  // sit far from the newest end (the reader scrolled up), and it must jump
  // the queue. Scanning the loaded list is cheap next to a translation call.
  for (final message in messages.reversed) {
    if (message.id <= 0 ||
        message.isOutgoing ||
        message.isService ||
        message.isTranslating ||
        excludedMessageIds.contains(message.id) ||
        automaticTranslationSourceText(message).trim().isEmpty) {
      continue;
    }
    final hasTargetTranslation =
        (message.translationText?.trim().isNotEmpty ?? false) &&
        TranslationController.normalizeLanguageCode(
              message.translationLanguageCode,
            ) ==
            target;
    if (hasTargetTranslation) continue;
    (visibleMessageIds.contains(message.id) ? onScreen : rest).add(message);
  }
  return [...onScreen, ...rest].take(limit).toList(growable: false);
}

/// The messages an automatic translation pass may translate.
///
/// A pass walks EVERY message the transcript has loaded. It must never be fed
/// a newest-N window: paging older history (the user scrolling up) prepends
/// messages that are then permanently outside such a window, so "translate
/// this chat" silently stopped translating exactly the pages that arrived
/// after the switch was flipped.
///
/// Messages currently painted in the viewport come first ([visibleMessageIds])
/// so opening or scrolling a chat translates what the reader is looking at
/// before the background walk continues. [limit] only bounds how many leave
/// per pass — applying a translation notifies the view model, which schedules
/// the next pass, so the walk covers the rest of the loaded history after the
/// screen is done.
List<ChatMessage> automaticTranslationLoadedCandidates(
  List<ChatMessage> loadedMessages, {
  required String targetLanguageCode,
  Set<int> excludedMessageIds = const {},
  Set<int> visibleMessageIds = const {},
  int limit = 12,
}) => automaticTranslationCandidates(
  loadedMessages,
  targetLanguageCode: targetLanguageCode,
  excludedMessageIds: excludedMessageIds,
  visibleMessageIds: visibleMessageIds,
  limit: limit,
);

List<String> automaticTranslationLanguageSamples(
  List<ChatMessage> messages, {
  int maximumMessages = 16,
  int minimumMessageLength = 10,
}) {
  final samples = <String>[];
  for (final message in messages.reversed) {
    if (samples.length >= maximumMessages) break;
    if (message.isOutgoing || message.isService) continue;
    final source = automaticTranslationLanguageText(message);
    if (source.length < minimumMessageLength) continue;
    samples.add(source);
  }
  return samples.reversed.toList(growable: false);
}

String automaticTranslationLanguageSample(
  List<ChatMessage> messages, {
  int maximumMessages = 16,
  int minimumMessageLength = 10,
}) => automaticTranslationLanguageSamples(
  messages,
  maximumMessages: maximumMessages,
  minimumMessageLength: minimumMessageLength,
).join('\n');

class AutomaticTranslationLanguageEvidence {
  const AutomaticTranslationLanguageEvidence({
    required this.languageCode,
    required this.confidence,
    required this.characterCount,
  });

  final String languageCode;
  final double confidence;
  final int characterCount;
}

String? dominantAutomaticTranslationLanguage(
  Iterable<AutomaticTranslationLanguageEvidence> evidence,
) {
  final weights = <String, double>{};
  for (final item in evidence) {
    final language = TranslationController.normalizeLanguageCode(
      item.languageCode,
    );
    if (language == null ||
        language == 'und' ||
        item.confidence <= 0 ||
        item.characterCount <= 0) {
      continue;
    }
    weights.update(
      language,
      (weight) => weight + item.characterCount * item.confidence,
      ifAbsent: () => item.characterCount * item.confidence,
    );
  }
  if (weights.isEmpty) return null;
  return weights.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}
