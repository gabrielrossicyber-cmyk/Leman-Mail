/// Pure helpers shared by the analysis engines. No Flutter dependency.
abstract final class EmailUtils {
  static final _addressRegex = RegExp(
    r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
  );

  /// Extracts the domain (lowercase) of an email address, or null.
  static String? domainOf(String? address) {
    if (address == null) return null;
    final at = address.lastIndexOf('@');
    if (at < 0 || at == address.length - 1) return null;
    return address.substring(at + 1).trim().toLowerCase();
  }

  /// Returns the registrable part heuristically ("mail.paypal.com" -> "paypal.com").
  /// Good enough for lookalike comparison without a full public-suffix list;
  /// handles common two-part ccTLDs (co.uk, com.au, ...).
  static String registrableDomain(String domain) {
    final parts = domain.toLowerCase().split('.');
    if (parts.length <= 2) return domain.toLowerCase();
    const secondLevel = {'co', 'com', 'net', 'org', 'gov', 'ac', 'edu'};
    if (parts[parts.length - 2].length <= 3 &&
        secondLevel.contains(parts[parts.length - 2])) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return parts.sublist(parts.length - 2).join('.');
  }

  /// Finds every email address occurring in [text].
  static List<String> extractAddresses(String text) =>
      _addressRegex.allMatches(text).map((m) => m.group(0)!).toList();

  /// Damerau-Levenshtein distance — used for typosquatting detection.
  static int editDistance(String a, String b) {
    if (a == b) return 0;
    final la = a.length, lb = b.length;
    if (la == 0) return lb;
    if (lb == 0) return la;
    final d = List.generate(la + 1, (_) => List.filled(lb + 1, 0));
    for (var i = 0; i <= la; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= lb; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= la; i++) {
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var best = d[i - 1][j] + 1;
        if (d[i][j - 1] + 1 < best) best = d[i][j - 1] + 1;
        if (d[i - 1][j - 1] + cost < best) best = d[i - 1][j - 1] + cost;
        // transposition
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1] &&
            d[i - 2][j - 2] + 1 < best) {
          best = d[i - 2][j - 2] + 1;
        }
        d[i][j] = best;
      }
    }
    return d[la][lb];
  }

  /// Normalizes common homoglyph substitutions (payp4l -> paypal, g00gle -> google).
  static String normalizeHomoglyphs(String input) {
    const map = {
      '0': 'o',
      '1': 'l',
      '3': 'e',
      '4': 'a',
      '5': 's',
      '7': 't',
      '@': 'a',
      r'$': 's',
      'а': 'a', // cyrillic а
      'е': 'e', // cyrillic е
      'о': 'o', // cyrillic о
      'і': 'i', // cyrillic і
      'ѕ': 's', // cyrillic ѕ
    };
    final sb = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  /// Extracts all http(s) URLs from plain text or HTML source.
  static List<Uri> extractUrls(String text) {
    final regex = RegExp(r'''https?://[^\s"'<>\)\]]+''', caseSensitive: false);
    final urls = <Uri>[];
    for (final m in regex.allMatches(text)) {
      final raw = m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.host.isNotEmpty) urls.add(uri);
    }
    return urls;
  }
}
