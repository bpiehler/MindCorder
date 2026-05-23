// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $NotesTable extends Notes with TableInfo<$NotesTable, Note> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _watchIdMeta = const VerificationMeta(
    'watchId',
  );
  @override
  late final GeneratedColumn<int> watchId = GeneratedColumn<int>(
    'watch_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryTitleMeta = const VerificationMeta(
    'summaryTitle',
  );
  @override
  late final GeneratedColumn<String> summaryTitle = GeneratedColumn<String>(
    'summary_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryBodyMeta = const VerificationMeta(
    'summaryBody',
  );
  @override
  late final GeneratedColumn<String> summaryBody = GeneratedColumn<String>(
    'summary_body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyPlainTextMeta = const VerificationMeta(
    'bodyPlainText',
  );
  @override
  late final GeneratedColumn<String> bodyPlainText = GeneratedColumn<String>(
    'body_plain_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _aiProviderMeta = const VerificationMeta(
    'aiProvider',
  );
  @override
  late final GeneratedColumn<String> aiProvider = GeneratedColumn<String>(
    'ai_provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processingStatusMeta = const VerificationMeta(
    'processingStatus',
  );
  @override
  late final GeneratedColumn<String> processingStatus = GeneratedColumn<String>(
    'processing_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    watchId,
    createdAt,
    rawText,
    summaryTitle,
    summaryBody,
    bodyPlainText,
    isArchived,
    isPinned,
    aiProvider,
    processingStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Note> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('watch_id')) {
      context.handle(
        _watchIdMeta,
        watchId.isAcceptableOrUnknown(data['watch_id']!, _watchIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
      );
    } else if (isInserting) {
      context.missing(_rawTextMeta);
    }
    if (data.containsKey('summary_title')) {
      context.handle(
        _summaryTitleMeta,
        summaryTitle.isAcceptableOrUnknown(
          data['summary_title']!,
          _summaryTitleMeta,
        ),
      );
    }
    if (data.containsKey('summary_body')) {
      context.handle(
        _summaryBodyMeta,
        summaryBody.isAcceptableOrUnknown(
          data['summary_body']!,
          _summaryBodyMeta,
        ),
      );
    }
    if (data.containsKey('body_plain_text')) {
      context.handle(
        _bodyPlainTextMeta,
        bodyPlainText.isAcceptableOrUnknown(
          data['body_plain_text']!,
          _bodyPlainTextMeta,
        ),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('ai_provider')) {
      context.handle(
        _aiProviderMeta,
        aiProvider.isAcceptableOrUnknown(data['ai_provider']!, _aiProviderMeta),
      );
    }
    if (data.containsKey('processing_status')) {
      context.handle(
        _processingStatusMeta,
        processingStatus.isAcceptableOrUnknown(
          data['processing_status']!,
          _processingStatusMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Note(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      watchId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watch_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      )!,
      summaryTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_title'],
      ),
      summaryBody: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_body'],
      ),
      bodyPlainText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_plain_text'],
      ),
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      aiProvider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_provider'],
      ),
      processingStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_status'],
      )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class Note extends DataClass implements Insertable<Note> {
  final int id;
  final int? watchId;
  final DateTime createdAt;
  final String rawText;
  final String? summaryTitle;
  final String? summaryBody;
  final String? bodyPlainText;
  final bool isArchived;
  final bool isPinned;
  final String? aiProvider;
  final String processingStatus;
  const Note({
    required this.id,
    this.watchId,
    required this.createdAt,
    required this.rawText,
    this.summaryTitle,
    this.summaryBody,
    this.bodyPlainText,
    required this.isArchived,
    required this.isPinned,
    this.aiProvider,
    required this.processingStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || watchId != null) {
      map['watch_id'] = Variable<int>(watchId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['raw_text'] = Variable<String>(rawText);
    if (!nullToAbsent || summaryTitle != null) {
      map['summary_title'] = Variable<String>(summaryTitle);
    }
    if (!nullToAbsent || summaryBody != null) {
      map['summary_body'] = Variable<String>(summaryBody);
    }
    if (!nullToAbsent || bodyPlainText != null) {
      map['body_plain_text'] = Variable<String>(bodyPlainText);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    map['is_pinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || aiProvider != null) {
      map['ai_provider'] = Variable<String>(aiProvider);
    }
    map['processing_status'] = Variable<String>(processingStatus);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      watchId: watchId == null && nullToAbsent
          ? const Value.absent()
          : Value(watchId),
      createdAt: Value(createdAt),
      rawText: Value(rawText),
      summaryTitle: summaryTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryTitle),
      summaryBody: summaryBody == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryBody),
      bodyPlainText: bodyPlainText == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyPlainText),
      isArchived: Value(isArchived),
      isPinned: Value(isPinned),
      aiProvider: aiProvider == null && nullToAbsent
          ? const Value.absent()
          : Value(aiProvider),
      processingStatus: Value(processingStatus),
    );
  }

  factory Note.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<int>(json['id']),
      watchId: serializer.fromJson<int?>(json['watchId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      rawText: serializer.fromJson<String>(json['rawText']),
      summaryTitle: serializer.fromJson<String?>(json['summaryTitle']),
      summaryBody: serializer.fromJson<String?>(json['summaryBody']),
      bodyPlainText: serializer.fromJson<String?>(json['bodyPlainText']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      aiProvider: serializer.fromJson<String?>(json['aiProvider']),
      processingStatus: serializer.fromJson<String>(json['processingStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'watchId': serializer.toJson<int?>(watchId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'rawText': serializer.toJson<String>(rawText),
      'summaryTitle': serializer.toJson<String?>(summaryTitle),
      'summaryBody': serializer.toJson<String?>(summaryBody),
      'bodyPlainText': serializer.toJson<String?>(bodyPlainText),
      'isArchived': serializer.toJson<bool>(isArchived),
      'isPinned': serializer.toJson<bool>(isPinned),
      'aiProvider': serializer.toJson<String?>(aiProvider),
      'processingStatus': serializer.toJson<String>(processingStatus),
    };
  }

  Note copyWith({
    int? id,
    Value<int?> watchId = const Value.absent(),
    DateTime? createdAt,
    String? rawText,
    Value<String?> summaryTitle = const Value.absent(),
    Value<String?> summaryBody = const Value.absent(),
    Value<String?> bodyPlainText = const Value.absent(),
    bool? isArchived,
    bool? isPinned,
    Value<String?> aiProvider = const Value.absent(),
    String? processingStatus,
  }) => Note(
    id: id ?? this.id,
    watchId: watchId.present ? watchId.value : this.watchId,
    createdAt: createdAt ?? this.createdAt,
    rawText: rawText ?? this.rawText,
    summaryTitle: summaryTitle.present ? summaryTitle.value : this.summaryTitle,
    summaryBody: summaryBody.present ? summaryBody.value : this.summaryBody,
    bodyPlainText: bodyPlainText.present
        ? bodyPlainText.value
        : this.bodyPlainText,
    isArchived: isArchived ?? this.isArchived,
    isPinned: isPinned ?? this.isPinned,
    aiProvider: aiProvider.present ? aiProvider.value : this.aiProvider,
    processingStatus: processingStatus ?? this.processingStatus,
  );
  Note copyWithCompanion(NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      watchId: data.watchId.present ? data.watchId.value : this.watchId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      summaryTitle: data.summaryTitle.present
          ? data.summaryTitle.value
          : this.summaryTitle,
      summaryBody: data.summaryBody.present
          ? data.summaryBody.value
          : this.summaryBody,
      bodyPlainText: data.bodyPlainText.present
          ? data.bodyPlainText.value
          : this.bodyPlainText,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      aiProvider: data.aiProvider.present
          ? data.aiProvider.value
          : this.aiProvider,
      processingStatus: data.processingStatus.present
          ? data.processingStatus.value
          : this.processingStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('watchId: $watchId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rawText: $rawText, ')
          ..write('summaryTitle: $summaryTitle, ')
          ..write('summaryBody: $summaryBody, ')
          ..write('bodyPlainText: $bodyPlainText, ')
          ..write('isArchived: $isArchived, ')
          ..write('isPinned: $isPinned, ')
          ..write('aiProvider: $aiProvider, ')
          ..write('processingStatus: $processingStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    watchId,
    createdAt,
    rawText,
    summaryTitle,
    summaryBody,
    bodyPlainText,
    isArchived,
    isPinned,
    aiProvider,
    processingStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Note &&
          other.id == this.id &&
          other.watchId == this.watchId &&
          other.createdAt == this.createdAt &&
          other.rawText == this.rawText &&
          other.summaryTitle == this.summaryTitle &&
          other.summaryBody == this.summaryBody &&
          other.bodyPlainText == this.bodyPlainText &&
          other.isArchived == this.isArchived &&
          other.isPinned == this.isPinned &&
          other.aiProvider == this.aiProvider &&
          other.processingStatus == this.processingStatus);
}

class NotesCompanion extends UpdateCompanion<Note> {
  final Value<int> id;
  final Value<int?> watchId;
  final Value<DateTime> createdAt;
  final Value<String> rawText;
  final Value<String?> summaryTitle;
  final Value<String?> summaryBody;
  final Value<String?> bodyPlainText;
  final Value<bool> isArchived;
  final Value<bool> isPinned;
  final Value<String?> aiProvider;
  final Value<String> processingStatus;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.watchId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rawText = const Value.absent(),
    this.summaryTitle = const Value.absent(),
    this.summaryBody = const Value.absent(),
    this.bodyPlainText = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.aiProvider = const Value.absent(),
    this.processingStatus = const Value.absent(),
  });
  NotesCompanion.insert({
    this.id = const Value.absent(),
    this.watchId = const Value.absent(),
    this.createdAt = const Value.absent(),
    required String rawText,
    this.summaryTitle = const Value.absent(),
    this.summaryBody = const Value.absent(),
    this.bodyPlainText = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.aiProvider = const Value.absent(),
    this.processingStatus = const Value.absent(),
  }) : rawText = Value(rawText);
  static Insertable<Note> custom({
    Expression<int>? id,
    Expression<int>? watchId,
    Expression<DateTime>? createdAt,
    Expression<String>? rawText,
    Expression<String>? summaryTitle,
    Expression<String>? summaryBody,
    Expression<String>? bodyPlainText,
    Expression<bool>? isArchived,
    Expression<bool>? isPinned,
    Expression<String>? aiProvider,
    Expression<String>? processingStatus,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (watchId != null) 'watch_id': watchId,
      if (createdAt != null) 'created_at': createdAt,
      if (rawText != null) 'raw_text': rawText,
      if (summaryTitle != null) 'summary_title': summaryTitle,
      if (summaryBody != null) 'summary_body': summaryBody,
      if (bodyPlainText != null) 'body_plain_text': bodyPlainText,
      if (isArchived != null) 'is_archived': isArchived,
      if (isPinned != null) 'is_pinned': isPinned,
      if (aiProvider != null) 'ai_provider': aiProvider,
      if (processingStatus != null) 'processing_status': processingStatus,
    });
  }

  NotesCompanion copyWith({
    Value<int>? id,
    Value<int?>? watchId,
    Value<DateTime>? createdAt,
    Value<String>? rawText,
    Value<String?>? summaryTitle,
    Value<String?>? summaryBody,
    Value<String?>? bodyPlainText,
    Value<bool>? isArchived,
    Value<bool>? isPinned,
    Value<String?>? aiProvider,
    Value<String>? processingStatus,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      watchId: watchId ?? this.watchId,
      createdAt: createdAt ?? this.createdAt,
      rawText: rawText ?? this.rawText,
      summaryTitle: summaryTitle ?? this.summaryTitle,
      summaryBody: summaryBody ?? this.summaryBody,
      bodyPlainText: bodyPlainText ?? this.bodyPlainText,
      isArchived: isArchived ?? this.isArchived,
      isPinned: isPinned ?? this.isPinned,
      aiProvider: aiProvider ?? this.aiProvider,
      processingStatus: processingStatus ?? this.processingStatus,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (watchId.present) {
      map['watch_id'] = Variable<int>(watchId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (summaryTitle.present) {
      map['summary_title'] = Variable<String>(summaryTitle.value);
    }
    if (summaryBody.present) {
      map['summary_body'] = Variable<String>(summaryBody.value);
    }
    if (bodyPlainText.present) {
      map['body_plain_text'] = Variable<String>(bodyPlainText.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (aiProvider.present) {
      map['ai_provider'] = Variable<String>(aiProvider.value);
    }
    if (processingStatus.present) {
      map['processing_status'] = Variable<String>(processingStatus.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('watchId: $watchId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rawText: $rawText, ')
          ..write('summaryTitle: $summaryTitle, ')
          ..write('summaryBody: $summaryBody, ')
          ..write('bodyPlainText: $bodyPlainText, ')
          ..write('isArchived: $isArchived, ')
          ..write('isPinned: $isPinned, ')
          ..write('aiProvider: $aiProvider, ')
          ..write('processingStatus: $processingStatus')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $NotesTable notes = $NotesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [notes];
}

typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      Value<int> id,
      Value<int?> watchId,
      Value<DateTime> createdAt,
      required String rawText,
      Value<String?> summaryTitle,
      Value<String?> summaryBody,
      Value<String?> bodyPlainText,
      Value<bool> isArchived,
      Value<bool> isPinned,
      Value<String?> aiProvider,
      Value<String> processingStatus,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<int> id,
      Value<int?> watchId,
      Value<DateTime> createdAt,
      Value<String> rawText,
      Value<String?> summaryTitle,
      Value<String?> summaryBody,
      Value<String?> bodyPlainText,
      Value<bool> isArchived,
      Value<bool> isPinned,
      Value<String?> aiProvider,
      Value<String> processingStatus,
    });

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchId => $composableBuilder(
    column: $table.watchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryTitle => $composableBuilder(
    column: $table.summaryTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryBody => $composableBuilder(
    column: $table.summaryBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyPlainText => $composableBuilder(
    column: $table.bodyPlainText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processingStatus => $composableBuilder(
    column: $table.processingStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchId => $composableBuilder(
    column: $table.watchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryTitle => $composableBuilder(
    column: $table.summaryTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryBody => $composableBuilder(
    column: $table.summaryBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyPlainText => $composableBuilder(
    column: $table.bodyPlainText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processingStatus => $composableBuilder(
    column: $table.processingStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get watchId =>
      $composableBuilder(column: $table.watchId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<String> get summaryTitle => $composableBuilder(
    column: $table.summaryTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summaryBody => $composableBuilder(
    column: $table.summaryBody,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bodyPlainText => $composableBuilder(
    column: $table.bodyPlainText,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<String> get aiProvider => $composableBuilder(
    column: $table.aiProvider,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processingStatus => $composableBuilder(
    column: $table.processingStatus,
    builder: (column) => column,
  );
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          Note,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (Note, BaseReferences<_$AppDatabase, $NotesTable, Note>),
          Note,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> watchId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> rawText = const Value.absent(),
                Value<String?> summaryTitle = const Value.absent(),
                Value<String?> summaryBody = const Value.absent(),
                Value<String?> bodyPlainText = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<String?> aiProvider = const Value.absent(),
                Value<String> processingStatus = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                watchId: watchId,
                createdAt: createdAt,
                rawText: rawText,
                summaryTitle: summaryTitle,
                summaryBody: summaryBody,
                bodyPlainText: bodyPlainText,
                isArchived: isArchived,
                isPinned: isPinned,
                aiProvider: aiProvider,
                processingStatus: processingStatus,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> watchId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                required String rawText,
                Value<String?> summaryTitle = const Value.absent(),
                Value<String?> summaryBody = const Value.absent(),
                Value<String?> bodyPlainText = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<String?> aiProvider = const Value.absent(),
                Value<String> processingStatus = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                watchId: watchId,
                createdAt: createdAt,
                rawText: rawText,
                summaryTitle: summaryTitle,
                summaryBody: summaryBody,
                bodyPlainText: bodyPlainText,
                isArchived: isArchived,
                isPinned: isPinned,
                aiProvider: aiProvider,
                processingStatus: processingStatus,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      Note,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (Note, BaseReferences<_$AppDatabase, $NotesTable, Note>),
      Note,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
}
