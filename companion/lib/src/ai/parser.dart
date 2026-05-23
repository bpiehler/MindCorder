import 'dart:convert';

class AIParser {
  static const String systemPrompt = 
      'Format the following messy transcript into a clean, concise summary. '
      'Return ONLY a valid JSON object wrapped inside <output_json>...</output_json> XML tags with exactly two fields:\n'
      '"title": a short descriptive title for the note (max 8 words),\n'
      '"body": structured bullet points in Markdown (max 5 bullets, remove filler words, organize key points logically).\n'
      'Do not include any pre- or post-conversational text. Example output:\n'
      '<output_json>\n'
      '{\n'
      '  "title": "Meeting with Client",\n'
      '  "body": "- Discussed project timeline\\n- Agreed on deliverables\\n- Next meeting scheduled for Friday"\n'
      '}\n'
      '</output_json>';

  /// Extracts the JSON summary from the raw AI model response.
  /// Handles XML tag wrapping, markdown code fences, and fallbacks.
  static Map<String, String> parseAIResponse(String response) {
    String cleanResponse = response.trim();
    
    // 1. Try to extract from <output_json> tags
    final tagRegex = RegExp(r'<output_json>(.*?)</output_json>', dotAll: true);
    final match = tagRegex.firstMatch(cleanResponse);
    String jsonCandidate = '';
    if (match != null) {
      jsonCandidate = match.group(1)?.trim() ?? '';
    } else {
      // 2. Fallback: Search for the outermost JSON block { ... }
      final jsonRegex = RegExp(r'(\{.*\})', dotAll: true);
      final jsonMatch = jsonRegex.firstMatch(cleanResponse);
      if (jsonMatch != null) {
        jsonCandidate = jsonMatch.group(1)?.trim() ?? '';
      }
    }

    if (jsonCandidate.isNotEmpty) {
      try {
        // Strip out potential markdown code fences wrapped around/inside
        if (jsonCandidate.startsWith('```json')) {
          jsonCandidate = jsonCandidate.substring(7);
        }
        if (jsonCandidate.endsWith('```')) {
          jsonCandidate = jsonCandidate.substring(0, jsonCandidate.length - 3);
        }
        jsonCandidate = jsonCandidate.trim();

        final parsed = json.decode(jsonCandidate);
        if (parsed is Map) {
          final title = parsed['title']?.toString() ?? 'Untitled';
          final body = parsed['body']?.toString() ?? 'No summary generated';
          return {
            'title': title,
            'body': body,
          };
        }
      } catch (_) {
        // Parsing failed, proceed to fallback
      }
    }

    // 3. Absolute Fallback: Treat raw response as body, extract first sentence as title
    String body = cleanResponse;
    String title = 'Untitled';
    if (cleanResponse.isNotEmpty) {
      final firstPeriod = cleanResponse.indexOf('.');
      if (firstPeriod != -1) {
        title = cleanResponse.substring(0, firstPeriod).trim();
        if (title.length > 40) {
          title = '${title.substring(0, 37)}...';
        }
      } else {
        title = cleanResponse.length > 30 ? '${cleanResponse.substring(0, 27)}...' : cleanResponse;
      }
    }
    
    return {
      'title': title,
      'body': body,
    };
  }

  /// Strips Markdown symbols and formatting to render beautifully as plain text on the Pebble watch.
  static String convertMarkdownToPlainText(String markdown) {
    if (markdown.isEmpty) return '';

    List<String> lines = markdown.split('\n');
    List<String> processedLines = [];

    for (var line in lines) {
      String processed = line;

      // 1. Convert headers: `# Header` -> `HEADER` (uppercase)
      if (processed.startsWith('#')) {
        int hashCount = 0;
        while (hashCount < processed.length && processed[hashCount] == '#') {
          hashCount++;
        }
        processed = processed.substring(hashCount).trim().toUpperCase();
      }

      // 2. Convert bullet markers: `- `, `* `, `+ ` -> `• ` (standard Pebble unicode bullet)
      final bulletRegex = RegExp(r'^(\s*)[-*+]\s+');
      if (bulletRegex.hasMatch(processed)) {
        processed = processed.replaceFirstMapped(bulletRegex, (match) {
          final indent = match.group(1) ?? '';
          return '$indent• ';
        });
      }

      // 3. Strip bold: `**bold**` or `__bold__` -> `bold`
      processed = processed.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (match) => match.group(1) ?? '');
      processed = processed.replaceAllMapped(RegExp(r'__([^_]+)__'), (match) => match.group(1) ?? '');

      // 4. Strip italic: `*italic*` or `_italic_` -> `italic`
      processed = processed.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (match) => match.group(1) ?? '');
      processed = processed.replaceAllMapped(RegExp(r'_([^_]+)_'), (match) => match.group(1) ?? '');

      // 5. Strip inline code: `` `code` `` -> `code`
      processed = processed.replaceAllMapped(RegExp(r'`([^`]+)`'), (match) => match.group(1) ?? '');

      processedLines.add(processed);
    }

    return processedLines.join('\n');
  }
}
