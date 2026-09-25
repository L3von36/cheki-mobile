import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Minimal PDF text extractor built for bank receipt PDFs.
///
/// Bank receipt PDFs (Dashen, Zemen) are machine-generated single-page
/// documents: content streams are FlateDecode-compressed and text is drawn
/// with simple `Tj` / `TJ` operators in a WinAnsi-compatible encoding.
/// This extractor:
///   1. scans the raw bytes for `stream ... endstream` sections,
///   2. inflates each section (zlib, then raw deflate, then as-is),
///   3. walks the content operators and pulls out every PDF string,
///   4. emits a plain-text line structure (newlines on positioning ops).
///
/// It is intentionally dependency-free and tuned for reliability over
/// completeness: any text it cannot recover is simply skipped, and the
/// verifier falls back to a "view original receipt" action.

/// Extracts readable text from a PDF byte stream.
/// Returns an empty string when nothing could be recovered.
String extractPdfText(Uint8List bytes) {
  if (bytes.length < 8) return '';

  final header = latin1.decode(bytes.sublist(0, 5), allowInvalid: true);
  if (!header.startsWith('%PDF')) return '';

  final content = _collectContentStreams(bytes);
  if (content.isEmpty) return '';
  return _extractStrings(content);
}

/// Finds every `stream ... endstream` section and returns the concatenated,
/// inflated content.
String _collectContentStreams(Uint8List bytes) {
  final marker = latin1.encode('stream');
  final endMarker = latin1.encode('endstream');
  final buffer = StringBuffer();

  var i = 0;
  while (true) {
    final start = _indexOf(bytes, marker, i);
    if (start < 0) break;

    // Skip the EOL right after "stream" (\r\n, \n or \r).
    var dataStart = start + marker.length;
    if (dataStart < bytes.length && bytes[dataStart] == 0x0D) dataStart++;
    if (dataStart < bytes.length && bytes[dataStart] == 0x0A) dataStart++;

    final end = _indexOf(bytes, endMarker, dataStart);
    if (end < 0) break;

    var dataEnd = end;
    // Trim a preceding EOL before "endstream".
    if (dataEnd > dataStart && bytes[dataEnd - 1] == 0x0A) dataEnd--;
    if (dataEnd > dataStart && bytes[dataEnd - 1] == 0x0D) dataEnd--;

    if (dataEnd > dataStart) {
      final chunk = bytes.sublist(dataStart, dataEnd);
      buffer.write(_inflate(chunk));
    }
    i = end + endMarker.length;
  }
  return buffer.toString();
}

/// Inflates a PDF stream. Handles the filter chains bank PDFs actually use:
/// FlateDecode (plain zlib), ASCII85Decode + FlateDecode (ReportLab), raw
/// deflate, and an uncompressed passthrough for plain operator streams.
String _inflate(Uint8List chunk) {
  final candidates = <Uint8List>[chunk];
  final a85 = ascii85Decode(chunk);
  if (a85 != null) candidates.add(a85);

  for (final candidate in candidates) {
    for (final raw in const [false, true]) {
      try {
        final decoded = raw
            ? ZLibCodec(raw: true).decode(candidate)
            : ZLibCodec().decode(candidate);
        final text = latin1.decode(decoded, allowInvalid: true);
        if (_looksLikeOperators(text)) return text;
      } catch (_) {
        // Try the next strategy.
      }
    }
  }
  // Uncompressed content stream — keep it as-is if it looks like operators.
  final asText = latin1.decode(chunk, allowInvalid: true);
  if (_looksLikeOperators(asText)) return asText;
  return '';
}

bool _looksLikeOperators(String text) {
  if (!text.contains('Tj') && !text.contains('TJ')) return false;
  // Reject binary junk that merely happens to contain the letters.
  var printable = 0;
  final sample = text.length < 512 ? text.length : 512;
  for (var i = 0; i < sample; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0x20 && c < 0x7F || c == 0x0A || c == 0x0D || c == 0x09) {
      printable++;
    }
  }
  return printable / sample > 0.7;
}

/// Adobe ASCII85 decode (the PDF filter variant, without `<~` wrappers).
/// Returns null when the input is not valid ASCII85.
Uint8List? ascii85Decode(Uint8List input, {int start = 0, int? end}) {
  final stop = end ?? input.length;
  final out = BytesBuilder();
  final group = <int>[];

  for (var i = start; i < stop; i++) {
    final c = input[i];
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) continue; // whitespace
    if (c == 0x7E /* ~ */) {
      break; // '~>' EOD marker (or trailing junk) — done.
    }
    if (c == 0x7A /* z */) {
      if (group.isNotEmpty) return null;
      out.add([0, 0, 0, 0]);
      continue;
    }
    if (c < 33 /* ! */ || c > 117 /* u */) return null;
    group.add(c - 33);
    if (group.length == 5) {
      var v = 0;
      for (final g in group) {
        v = v * 85 + g;
      }
      v &= 0xFFFFFFFF;
      out.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
      group.clear();
    }
  }

  if (group.isNotEmpty) {
    if (group.length == 1) return null; // invalid final group
    final n = group.length;
    while (group.length < 5) {
      group.add(84); // pad with 'u'
    }
    var v = 0;
    for (final g in group) {
      v = v * 85 + g;
    }
    v &= 0xFFFFFFFF;
    out.add([
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ].sublist(0, n - 1));
  }
  return out.toBytes();
}

/// Walks content-stream operators and concatenates the drawn strings.
String _extractStrings(String content) {
  final buffer = StringBuffer();

  for (var i = 0; i < content.length; i++) {
    final ch = content[i];

    // Newline hints from text-positioning operators.
    if (_matchOp(content, i, 'Td') ||
        _matchOp(content, i, 'TD') ||
        _matchOp(content, i, 'T*') ||
        _matchOp(content, i, 'ET')) {
      buffer.write('\n');
      continue;
    }

    if (ch == '(') {
      final (str, next) = _readLiteralString(content, i);
      if (str.isNotEmpty) buffer.write(str);
      if (next > i) {
        i = next - 1;
        continue;
      }
    } else if (ch == '<' && i + 1 < content.length && content[i + 1] != '<') {
      final (str, next) = _readHexString(content, i);
      if (str.isNotEmpty) buffer.write(str);
      if (next > i) {
        i = next - 1;
        continue;
      }
    }
  }
  return _tidy(buffer.toString());
}

bool _matchOp(String s, int i, String op) {
  if (i + op.length > s.length) return false;
  if (s.substring(i, i + op.length) != op) return false;
  // The char before must not be alphanumeric (avoids matching inside words
  // like "endstream" when looking for "T" ops) and the char after must be a
  // delimiter or whitespace.
  final before = i > 0 ? s[i - 1] : ' ';
  final after = i + op.length < s.length ? s[i + op.length] : ' ';
  bool isWord(int c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  if (isWord(before.codeUnitAt(0))) return false;
  return after == ' ' || after == '\n' || after == '\r' || after == '\t';
}

/// Reads a PDF literal string `(...)` starting at [start] (which must be `(`).
/// Returns the decoded string and the index just after the closing `)`.
(String, int) _readLiteralString(String s, int start) {
  final out = StringBuffer();
  var depth = 1;
  var i = start + 1;
  while (i < s.length && depth > 0) {
    final ch = s[i];
    if (ch == '\\') {
      if (i + 1 >= s.length) break;
      final esc = s[i + 1];
      switch (esc) {
        case 'n':
          out.write('\n');
          i += 2;
        case 'r':
          i += 2;
        case 't':
          out.write('\t');
          i += 2;
        case 'b':
        case 'f':
          i += 2;
        case '(':
        case ')':
        case '\\':
          out.write(esc);
          i += 2;
        default:
          // Octal escape \ddd (up to 3 digits).
          if (esc.codeUnitAt(0) >= 0x30 && esc.codeUnitAt(0) <= 0x37) {
            var value = 0;
            var digits = 0;
            while (digits < 3 &&
                i + 1 < s.length &&
                s[i + 1].codeUnitAt(0) >= 0x30 &&
                s[i + 1].codeUnitAt(0) <= 0x37) {
              value = value * 8 + (s[i + 1].codeUnitAt(0) - 0x30);
              i++;
              digits++;
            }
            i++;
            if (value > 0) out.writeCharCode(value);
          } else {
            // Unknown escape — keep the char as-is.
            out.write(esc);
            i += 2;
          }
      }
      continue;
    }
    if (ch == '(') depth++;
    if (ch == ')') {
      depth--;
      if (depth == 0) return (out.toString(), i + 1);
    }
    out.write(ch);
    i++;
  }
  return (out.toString(), i < s.length ? i : s.length);
}

/// Reads a PDF hex string `<...>` starting at [start].
(String, int) _readHexString(String s, int start) {
  var end = start + 1;
  while (end < s.length && s[end] != '>') {
    end++;
  }
  if (end >= s.length) return ('', start);
  final hex = s.substring(start + 1, end).replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  if (hex.isEmpty) return ('', end + 1);

  // UTF-16BE detection (common for CID-encoded receipts): pairs of bytes
  // starting with 0x00-0xFF where odd-index bytes are mostly 0x00.
  if (hex.length % 4 == 0 && hex.length >= 4) {
    final isUtf16 = RegExp(r'^(00[2-9A-Fa-f])').hasMatch(hex);
    if (isUtf16) {
      final out = StringBuffer();
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        final code = int.tryParse(hex.substring(i, i + 4), radix: 16);
        if (code != null && code >= 0x20) out.writeCharCode(code);
      }
      return (out.toString(), end + 1);
    }
  }

  final out = StringBuffer();
  for (var i = 0; i + 2 <= hex.length; i += 2) {
    final byte = int.tryParse(hex.substring(i, i + 2), radix: 16) ?? 0;
    if (byte >= 0x20) out.writeCharCode(byte);
  }
  return (out.toString(), end + 1);
}

/// Normalizes whitespace: collapses runs of blank lines, trims each line.
String _tidy(String text) {
  return text
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}

int _indexOf(Uint8List bytes, List<int> pattern, int from) {
  if (pattern.isEmpty || bytes.length < pattern.length) return -1;
  outer:
  for (var i = from; i <= bytes.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}
