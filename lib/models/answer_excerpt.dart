/// A view onto the stored answer. The full text and citation offsets stay intact.
class AnswerExcerpt {
  final int start, end;
  final bool shortened;
  const AnswerExcerpt(this.start, this.end, {this.shortened = false});

  factory AnswerExcerpt.fromText(String text) {
    final details = RegExp(
      r'\n\s*(?:#{1,6}\s*)?Details:\s*\n',
      caseSensitive: false,
    ).firstMatch(text);
    final limit = details?.start ?? text.length;
    final paragraphs = RegExp(
      r'\S[\s\S]*?(?=\n\s*\n|$)',
    ).allMatches(text.substring(0, limit));
    var start = 0, end = limit;
    for (final paragraph in paragraphs) {
      final value = paragraph.group(0)!.trim();
      if (value.startsWith('#') || value == '---' || value.isEmpty) continue;
      if (value.length < 110 &&
          RegExp(r'^(hello|hi|hey)\b', caseSensitive: false).hasMatch(value)) {
        continue;
      }
      if (!RegExp(r'\d').hasMatch(value) && value.endsWith(':')) continue;
      start = paragraph.start;
      end = paragraph.end;
      break;
    }
    // Older answers did not have a separate conversational lead. Show a short
    // original excerpt instead of generating or saving a guessed summary.
    const maximum = 420;
    if (end - start > maximum) {
      final prefix = text.substring(start, start + maximum);
      final sentenceEnds = RegExp(r'[.!?](?:\s|$)').allMatches(prefix).toList();
      final boundary = sentenceEnds.isNotEmpty && sentenceEnds.last.start > 100
          ? sentenceEnds.last.start + 1
          : prefix.lastIndexOf(RegExp(r'\s'));
      end = start + (boundary > 0 ? boundary : maximum);
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end--;
    }
    return AnswerExcerpt(start, end, shortened: end < limit && details == null);
  }
}
