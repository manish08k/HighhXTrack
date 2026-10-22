import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Renders a lightweight markdown subset used by notes:
/// `# Heading`, `## Subheading`, `- bullet`, `1. item`, `> quote`,
/// `**bold**`, `*italic*`, `~~strike~~`.
class FormattedText extends StatelessWidget {
  const FormattedText(this.source, {super.key, this.maxLines});
  final String source;
  final int? maxLines;

  static final _inline = RegExp(r'(\*\*[^*]+\*\*|~~[^~]+~~|\*[^*]+\*)');

  static List<InlineSpan> inlineSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      final t = m.group(0)!;
      if (t.startsWith('**')) {
        spans.add(
          TextSpan(
            text: t.substring(2, t.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (t.startsWith('~~')) {
        spans.add(
          TextSpan(
            text: t.substring(2, t.length - 2),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: t.substring(1, t.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = context.text.bodyLarge!.copyWith(height: 1.45);
    final lines = source.split('\n');
    final children = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.startsWith('## ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text.rich(TextSpan(children: inlineSpans(line.substring(3), base)), style: context.text.titleMedium),
          ),
        );
      } else if (line.startsWith('# ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text.rich(TextSpan(children: inlineSpans(line.substring(2), base)), style: context.text.titleLarge),
          ),
        );
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: Text('•', style: base),
              ),
              Expanded(
                child: Text.rich(TextSpan(children: inlineSpans(line.substring(2), base)), style: base),
              ),
            ],
          ),
        );
      } else if (RegExp(r'^\d+\. ').hasMatch(line)) {
        final m = RegExp(r'^(\d+)\. ').firstMatch(line)!;
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 26, child: Text('${m.group(1)}.', style: base)),
              Expanded(
                child: Text.rich(TextSpan(children: inlineSpans(line.substring(m.end), base)), style: base),
              ),
            ],
          ),
        );
      } else if (line.startsWith('> ')) {
        children.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: context.colors.outlineVariant, width: 3)),
            ),
            child: Text.rich(
              TextSpan(children: inlineSpans(line.substring(2), base)),
              style: base.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        );
      } else if (line.isEmpty) {
        children.add(const SizedBox(height: 10));
      } else {
        children.add(Text.rich(TextSpan(children: inlineSpans(line, base)), style: base));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
