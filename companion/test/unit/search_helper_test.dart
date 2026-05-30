import 'package:flutter_test/flutter_test.dart';
import 'package:mindcorder_app/src/ui/search_helper.dart';

void main() {
  group('SemanticSearchEngine Tokenizer Tests', () {
    test('should clean and tokenize text successfully', () {
      final tokens = SemanticSearchEngine.tokenize('Hello, MindCorder World! This is a test.');
      expect(tokens, contains('hello'));
      expect(tokens, contains('mindcorder'));
      expect(tokens, contains('world'));
      expect(tokens, contains('test'));
      expect(tokens, isNot(contains('this'))); // Stop word
      expect(tokens, isNot(contains('is'))); // Stop word
      expect(tokens, isNot(contains('a'))); // Stop word
    });
  });

  group('SemanticSearchEngine Similarity Tests', () {
    test('should return 1.0 when query is empty', () {
      final score = SemanticSearchEngine.computeSimilarity(
        query: '   ',
        title: 'Weekly Standup Notes',
        body: 'Discussed the timeline UI and backend self-healing feature.',
        rawText: 'Discussed the timeline UI and backend self-healing feature.',
      );
      expect(score, equals(1.0));
    });

    test('should return 0.0 when there is no match at all', () {
      final score = SemanticSearchEngine.computeSimilarity(
        query: 'fitness exercises',
        title: 'Weekly Standup Notes',
        body: 'Discussed the timeline UI and backend self-healing feature.',
        rawText: 'Discussed the timeline UI and backend self-healing feature.',
      );
      expect(score, equals(0.0));
    });

    test('should return positive score on direct token overlap', () {
      final score = SemanticSearchEngine.computeSimilarity(
        query: 'timeline UI',
        title: 'Weekly Standup Notes',
        body: 'Discussed the timeline UI and backend self-healing feature.',
        rawText: 'Discussed the timeline UI and backend self-healing feature.',
      );
      expect(score, greaterThan(0.0));
    });

    test('should prioritize Title matches over Body matches', () {
      final titleScore = SemanticSearchEngine.computeSimilarity(
        query: 'standup',
        title: 'Weekly Standup Notes',
        body: 'Some regular notes here.',
        rawText: 'Some regular notes here.',
      );

      final bodyScore = SemanticSearchEngine.computeSimilarity(
        query: 'standup',
        title: 'Weekly Project Update',
        body: 'We had a standup and discussed tasks.',
        rawText: 'We had a standup and discussed tasks.',
      );

      // Both match "standup" once, but titleScore should rank higher because Title tokens have a 2.5 multiplier
      expect(titleScore, greaterThan(bodyScore));
    });

    test('should successfully expand semantic synonyms (grocery -> milk)', () {
      final exactScore = SemanticSearchEngine.computeSimilarity(
        query: 'groceries',
        title: 'Grocery checklist',
        body: 'Need to get some groceries from the supermarket.',
        rawText: 'Need to get some groceries.',
      );

      final semanticScore = SemanticSearchEngine.computeSimilarity(
        query: 'groceries',
        title: 'Items to buy',
        body: 'Need to get some milk, bread, and eggs from the store.',
        rawText: 'Need to get some milk.',
      );

      // The second note does not contain the word "groceries" or "grocery".
      // But because "groceries" expands to "milk", "store", "bread", etc., it gets a positive similarity score!
      expect(exactScore, greaterThan(0.0));
      expect(semanticScore, greaterThan(0.0));
    });

    test('should handle code and programming terminology mapping', () {
      final score = SemanticSearchEngine.computeSimilarity(
        query: 'coding',
        title: 'App optimization',
        body: 'Spent all afternoon writing flutter and dart widgets.',
        rawText: 'Spent all afternoon writing flutter and dart widgets.',
      );

      // "coding" expands to "flutter", "dart", etc.
      expect(score, greaterThan(0.0));
    });
  });
}
