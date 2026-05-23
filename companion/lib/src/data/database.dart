import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get watchId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get rawText => text()();
  TextColumn get summaryTitle => text().nullable()();
  TextColumn get summaryBody => text().nullable()();
  TextColumn get bodyPlainText => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  TextColumn get aiProvider => text().nullable()();
  TextColumn get processingStatus => text().withDefault(const Constant('pending'))();
}

@DriftDatabase(tables: [Notes])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'mindcorder',
    );
  }

  // DAO methods
  Stream<List<Note>> watchAllNotes() {
    return (select(notes)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<Note>> watchArchivedNotes() {
    return (select(notes)
          ..where((t) => t.isArchived.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<List<Note>> getAllNotes() {
    return (select(notes)
          ..orderBy([
            (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<Note?> getNoteById(int id) {
    return (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Note?> getNoteByWatchId(int watchId) {
    return (select(notes)..where((t) => t.watchId.equals(watchId))).getSingleOrNull();
  }

  Future<int> insertNote(NotesCompanion entry) {
    return into(notes).insert(entry);
  }

  Future<bool> updateNoteEntry(Note entry) {
    return update(notes).replace(entry);
  }

  Future<int> deleteNoteById(int id) {
    return (delete(notes)..where((t) => t.id.equals(id))).go();
  }
}
