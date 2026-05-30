import '../data/database.dart';

class TimeframeGroup {
  final String title;
  final List<Note> notes;

  TimeframeGroup({required this.title, required this.notes});
}

class TimelineCategorizer {
  static List<TimeframeGroup> groupNotes(List<Note> notes) {
    if (notes.isEmpty) return [];

    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 7));
    final monthStart = DateTime(today.year, today.month, 1);

    final List<Note> todayNotes = [];
    final List<Note> yesterdayNotes = [];
    final List<Note> thisWeekNotes = [];
    final List<Note> thisMonthNotes = [];
    final Map<String, List<Note>> olderMonthNotes = {};

    for (final note in notes) {
      final noteDate = note.createdAt;
      if (noteDate.isAfter(todayStart)) {
        todayNotes.add(note);
      } else if (noteDate.isAfter(yesterdayStart)) {
        yesterdayNotes.add(note);
      } else if (noteDate.isAfter(weekStart)) {
        thisWeekNotes.add(note);
      } else if (noteDate.isAfter(monthStart)) {
        thisMonthNotes.add(note);
      } else {
        final monthKey = "${_getMonthName(noteDate.month)} ${noteDate.year}";
        if (!olderMonthNotes.containsKey(monthKey)) {
          olderMonthNotes[monthKey] = [];
        }
        olderMonthNotes[monthKey]!.add(note);
      }
    }

    final List<TimeframeGroup> groups = [];
    if (todayNotes.isNotEmpty) {
      groups.add(TimeframeGroup(title: 'TODAY', notes: todayNotes));
    }
    if (yesterdayNotes.isNotEmpty) {
      groups.add(TimeframeGroup(title: 'YESTERDAY', notes: yesterdayNotes));
    }
    if (thisWeekNotes.isNotEmpty) {
      groups.add(TimeframeGroup(title: 'THIS WEEK', notes: thisWeekNotes));
    }
    if (thisMonthNotes.isNotEmpty) {
      groups.add(TimeframeGroup(title: 'THIS MONTH', notes: thisMonthNotes));
    }

    // Sort older months descending
    final sortedMonths = olderMonthNotes.keys.toList()
      ..sort((a, b) {
        final aDate = olderMonthNotes[a]!.first.createdAt;
        final bDate = olderMonthNotes[b]!.first.createdAt;
        return bDate.compareTo(aDate);
      });

    for (final month in sortedMonths) {
      groups.add(TimeframeGroup(title: month.toUpperCase(), notes: olderMonthNotes[month]!));
    }

    return groups;
  }

  static String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    if (month >= 1 && month <= 12) {
      return months[month - 1];
    }
    return '';
  }
}
