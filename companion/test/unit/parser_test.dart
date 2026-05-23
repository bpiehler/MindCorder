import 'package:flutter_test/flutter_test.dart';
import 'package:mindcorder_app/src/ai/parser.dart';

void main() {
  group('AI response parser', () {
    test('should extract valid JSON inside XML tags', () {
      const response = '''
Some conversational prefix text.
<output_json>
{
  "title": "Clean Title",
  "body": "- Bullet 1\\n- Bullet 2"
}
</output_json>
Some suffix text.
''';
      final result = AIParser.parseAIResponse(response);
      expect(result['title'], equals('Clean Title'));
      expect(result['body'], equals('- Bullet 1\n- Bullet 2'));
    });

    test('should fallback to outer curly brackets JSON if tags missing', () {
      const response = '''
No tags here, but here is the JSON:
{
  "title": "Fallback Title",
  "body": "- Yes bullet"
}
And some trailing words.
''';
      final result = AIParser.parseAIResponse(response);
      expect(result['title'], equals('Fallback Title'));
      expect(result['body'], equals('- Yes bullet'));
    });

    test('should handle markdown code fences inside candidates', () {
      const response = '''
<output_json>
```json
{
  "title": "Fenced Title",
  "body": "- Fenced"
}
```
</output_json>
''';
      final result = AIParser.parseAIResponse(response);
      expect(result['title'], equals('Fenced Title'));
      expect(result['body'], equals('- Fenced'));
    });

    test('should return whole raw response as body if not JSON', () {
      const response = 'Meeting with team. We discussed launch dates for Phase 2. Next week is code freeze.';
      final result = AIParser.parseAIResponse(response);
      expect(result['title'], equals('Meeting with team'));
      expect(result['body'], equals(response));
    });
  });

  group('Markdown converter for watch', () {
    test('should strip headers and capitalise', () {
      expect(AIParser.convertMarkdownToPlainText('# Top Header'), equals('TOP HEADER'));
      expect(AIParser.convertMarkdownToPlainText('## Sub Header'), equals('SUB HEADER'));
    });

    test('should replace markdown bullets with unicode bullets', () {
      expect(AIParser.convertMarkdownToPlainText('- bullet 1'), equals('• bullet 1'));
      expect(AIParser.convertMarkdownToPlainText('* bullet 2'), equals('• bullet 2'));
      expect(AIParser.convertMarkdownToPlainText('  - bullet 3'), equals('  • bullet 3'));
    });

    test('should strip bold and italics', () {
      expect(AIParser.convertMarkdownToPlainText('This is **bold** text.'), equals('This is bold text.'));
      expect(AIParser.convertMarkdownToPlainText('This is *italic* text.'), equals('This is italic text.'));
      expect(AIParser.convertMarkdownToPlainText('Combine **bold** and *italic*.'), equals('Combine bold and italic.'));
    });

    test('should preserve line breaks', () {
      const input = 'Line 1\n- Line 2\n**Line 3**';
      const expected = 'Line 1\n• Line 2\nLine 3';
      expect(AIParser.convertMarkdownToPlainText(input), equals(expected));
    });
  });
}
