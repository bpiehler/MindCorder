import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindcorder_app/src/data/database.dart';
import 'package:drift/drift.dart' as drift;

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  group('Drift Database CRUD Queries', () {
    test('should insert and fetch a note by watchId and db id', () async {
      final companion = NotesCompanion.insert(
        watchId: const drift.Value(100),
        rawText: 'This is raw text from watch dictation',
        processingStatus: const drift.Value('completed'),
      );

      final id = await database.insertNote(companion);
      expect(id, greaterThan(0));

      final note = await database.getNoteById(id);
      expect(note, isNotNull);
      expect(note!.rawText, equals('This is raw text from watch dictation'));
      expect(note.watchId, equals(100));

      final noteByWatch = await database.getNoteByWatchId(100);
      expect(noteByWatch, isNotNull);
      expect(noteByWatch!.id, equals(id));
    });

    test('should sort all notes correctly (pinned first, then date descending)', () async {
      // 1. Note at t=100 (Unpinned)
      await database.insertNote(NotesCompanion.insert(
        watchId: const drift.Value(101),
        rawText: 't=100 note',
        createdAt: drift.Value(DateTime.fromMillisecondsSinceEpoch(100000)),
        processingStatus: const drift.Value('completed'),
      ));

      // 2. Note at t=200 (Unpinned)
      await database.insertNote(NotesCompanion.insert(
        watchId: const drift.Value(102),
        rawText: 't=200 note',
        createdAt: drift.Value(DateTime.fromMillisecondsSinceEpoch(200000)),
        processingStatus: const drift.Value('completed'),
      ));

      // 3. Note at t=150 (Pinned!)
      await database.insertNote(NotesCompanion.insert(
        watchId: const drift.Value(103),
        rawText: 't=150 pinned note',
        isPinned: const drift.Value(true),
        createdAt: drift.Value(DateTime.fromMillisecondsSinceEpoch(150000)),
        processingStatus: const drift.Value('completed'),
      ));

      final notes = await database.getAllNotes();
      expect(notes.length, equals(3));

      // First note should be Pinned note (t=150)
      expect(notes[0].watchId, equals(103));
      expect(notes[0].isPinned, isTrue);

      // Second note should be the newest unpinned note (t=200)
      expect(notes[1].watchId, equals(102));
      expect(notes[1].isPinned, isFalse);

      // Third note should be the older unpinned note (t=100)
      expect(notes[2].watchId, equals(101));
    });

    test('should archive notes and omit them from watchAllNotes list', () async {
      final id = await database.insertNote(NotesCompanion.insert(
        rawText: 'Memo to be archived',
      ));

      var notes = await database.watchAllNotes().first;
      expect(notes.length, equals(1));

      final note = notes.first;
      await database.updateNoteEntry(note.copyWith(isArchived: true));

      notes = await database.watchAllNotes().first;
      expect(notes.isEmpty, isTrue);

      final archivedNotes = await database.watchArchivedNotes().first;
      expect(archivedNotes.length, equals(1));
    });

    test('should delete note by ID', () async {
      final id = await database.insertNote(NotesCompanion.insert(
        rawText: 'Memo to be deleted',
      ));

      var note = await database.getNoteById(id);
      expect(note, isNotNull);

      await database.deleteNoteById(id);

      note = await database.getNoteById(id);
      expect(note, isNull);
    });
  });
}
