import 'package:flutter_test/flutter_test.dart';
import 'package:mindcorder_app/src/data/database.dart';
import 'package:mindcorder_app/src/ui/timeline_helper.dart';

void main() {
  group('TimelineCategorizer Note Grouping Tests', () {
    test('should return empty list when notes are empty', () {
      final groups = TimelineCategorizer.groupNotes([]);
      expect(groups, isEmpty);
    });

    test('should correctly group notes by Today, Yesterday, and Older Months', () {
      final now = DateTime.now();

      final todayNote = Note(
        id: 1,
        rawText: 'Today note',
        createdAt: now.subtract(const Duration(minutes: 5)),
        processingStatus: 'completed',
        isArchived: false,
        isPinned: false,
      );

      final yesterdayNote = Note(
        id: 2,
        rawText: 'Yesterday note',
        createdAt: now.subtract(const Duration(hours: 26)),
        processingStatus: 'completed',
        isArchived: false,
        isPinned: false,
      );

      final thisWeekNote = Note(
        id: 3,
        rawText: 'This week note',
        createdAt: now.subtract(const Duration(days: 4)),
        processingStatus: 'completed',
        isArchived: false,
        isPinned: false,
      );

      final olderNote = Note(
        id: 4,
        rawText: 'Older note',
        createdAt: DateTime(2026, 4, 15, 10, 0), // April 2026
        processingStatus: 'completed',
        isArchived: false,
        isPinned: false,
      );

      final List<Note> notes = [todayNote, yesterdayNote, thisWeekNote, olderNote];
      final groups = TimelineCategorizer.groupNotes(notes);

      expect(groups.length, equals(4));
      
      expect(groups[0].title, equals('TODAY'));
      expect(groups[0].notes.first.id, equals(1));

      expect(groups[1].title, equals('YESTERDAY'));
      expect(groups[1].notes.first.id, equals(2));

      expect(groups[2].title, equals('THIS WEEK'));
      expect(groups[2].notes.first.id, equals(3));

      expect(groups[3].title, equals('APRIL 2026'));
      expect(groups[3].notes.first.id, equals(4));
    });
  });
}
