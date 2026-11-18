import 'dart:convert';

/// Converts the small Markdown subset the old editor wrote (`**bold**`,
/// `*italic*`, `__underline__`) plus simple headings and bullets into Quill
/// Delta operations. Any other characters are kept verbatim, so no existing
/// note content can be lost.
List<Map<String, dynamic>> legacyMarkdownToDeltaOps(String text) {
  final ops = <Map<String, dynamic>>[];
  final source = text.replaceAll('\r\n', '\n');
  if (source.trim().isEmpty) {
    return [
      {'insert': '\n'},
    ];
  }

  var lines = source.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines = lines.sublist(0, lines.length - 1);
  }

  for (final line in lines) {
    var content = line;
    Map<String, dynamic>? blockAttributes;

    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    final bullet = RegExp(r'^[-\*\u2022]\s+(.*)$').firstMatch(line);
    final ordered = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(line);

    if (heading != null) {
      blockAttributes = {'header': heading.group(1)!.length};
      content = heading.group(2) ?? '';
    } else if (bullet != null) {
      blockAttributes = {'list': 'bullet'};
      content = bullet.group(1) ?? '';
    } else if (ordered != null) {
      blockAttributes = {'list': 'ordered'};
      content = ordered.group(1) ?? '';
    }

    _appendInlineOps(ops, content);
    final lineOp = <String, dynamic>{'insert': '\n'};
    if (blockAttributes != null) {
      lineOp['attributes'] = blockAttributes;
    }
    ops.add(lineOp);
  }

  if (ops.isEmpty) {
    ops.add({'insert': '\n'});
  }
  return ops;
}

void _appendInlineOps(List<Map<String, dynamic>> ops, String content) {
  if (content.isEmpty) return;
  final pattern = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*');
  var cursor = 0;
  for (final match in pattern.allMatches(content)) {
    if (match.start > cursor) {
      ops.add({'insert': content.substring(cursor, match.start)});
    }
    if (match.group(1) != null) {
      ops.add({
        'insert': match.group(1)!,
        'attributes': {'bold': true},
      });
    } else if (match.group(2) != null) {
      ops.add({
        'insert': match.group(2)!,
        'attributes': {'underline': true},
      });
    } else if (match.group(3) != null) {
      ops.add({
        'insert': match.group(3)!,
        'attributes': {'italic': true},
      });
    }
    cursor = match.end;
  }
  if (cursor < content.length) {
    ops.add({'insert': content.substring(cursor)});
  }
}

/// Rich representation used when scripture is saved into the main Notes
/// dashboard. The verse is visually quoted and the reference stays visible.
String buildScriptureDelta({
  required String verseText,
  required String reference,
  required String translationName,
  bool leaveRoomForReflection = false,
}) {
  final ops = <Map<String, dynamic>>[
    {
      'insert': '"$verseText"',
      'attributes': {'italic': true},
    },
    {'insert': '\n'},
    {
      'insert': reference,
      'attributes': {'bold': true},
    },
    {'insert': ' \u2014 $translationName'},
    {'insert': '\n'},
    if (leaveRoomForReflection) {'insert': '\n'},
  ];
  return jsonEncode(ops);
}

/// Plain-text companion stored with every rich note so search and previews
/// work without parsing Delta JSON.
String buildScripturePlainText({
  required String verseText,
  required String reference,
  required String translationName,
}) => '"$verseText"\n$reference \u2014 $translationName';
