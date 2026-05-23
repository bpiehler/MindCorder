import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:mindcorder_app/src/data/database.dart';
import 'package:mindcorder_app/src/ai/ai_service.dart';
import 'package:mindcorder_app/src/pebble/pebble_service.dart';

class MockAIService implements AIService {
  bool failNext = false;
  String customBody = '- Mock bullet 1\n- Mock bullet 2';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<SummaryResult> summarize(String rawText) async {
    if (failNext) {
      throw Exception("AI Model Error");
    }
    return SummaryResult(
      title: 'Mock Summary',
      body: customBody,
      provider: 'mock',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('mindcorder/pebble_methods');
  late AppDatabase database;
  late MockAIService aiService;
  late PebbleService pebbleService;
  late List<Map<String, dynamic>> sentMessages;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    aiService = MockAIService();
    pebbleService = PebbleService(
      database: database,
      aiService: aiService,
    );
    sentMessages = [];

    // Mock native MethodChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'sendToWatch') {
        final map = Map<String, dynamic>.from(methodCall.arguments as Map);
        sentMessages.add(map);
        return true;
      }
      if (methodCall.method == 'isWatchConnected') {
        return true;
      }
      return null;
    });
  });

  tearDown(() async {
    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('Pebble Bridge Communication Protocol', () {
    late int newSessionId;

    setUp(() {
      newSessionId = DateTime.now().millisecondsSinceEpoch + 100000;
    });

    test('should respond with Handshake ACK (COMMAND=0) to Handshake', () async {
      final watchHandshake = {
        'COMMAND': 0,
        'SESSION_ID': newSessionId,
        'MSG_ID': 1,
      };

      await pebbleService.handleWatchMessage(watchHandshake);

      expect(sentMessages.length, equals(1));
      expect(sentMessages[0]['COMMAND'], equals(0));
      expect(sentMessages[0]['SESSION_ID'], equals(newSessionId));
      expect(sentMessages[0]['MSG_ID'], greaterThan(0));
    });

    test('should process new dictation transcript, trigger AI, and return single-packet summary', () async {
      final watchUpload = {
        'COMMAND': 1,
        'RAW_TEXT': 'Hello world, this is a transcript',
        'NOTE_ID': 2026,
        'MSG_ID': 2,
        'SESSION_ID': newSessionId,
      };

      await pebbleService.handleWatchMessage(watchUpload);

      // Verify that note was inserted into Drift SQLite
      final notes = await database.getAllNotes();
      expect(notes.length, equals(1));
      expect(notes.first.watchId, equals(2026));
      expect(notes.first.rawText, equals('Hello world, this is a transcript'));
      expect(notes.first.processingStatus, equals('completed'));
      expect(notes.first.summaryTitle, equals('Mock Summary'));

      // Check messages sent to watch
      // First message: COMMAND=10 (Summarizing...)
      // Second message: COMMAND=14 (Complete single message summary)
      expect(sentMessages.length, equals(2));
      expect(sentMessages[0]['COMMAND'], equals(10));
      expect(sentMessages[0]['TITLE'], equals('Summarizing...'));

      expect(sentMessages[1]['COMMAND'], equals(14));
      expect(sentMessages[1]['TITLE'], equals('Mock Summary'));
      expect(sentMessages[1]['BODY'], contains('• Mock bullet 1')); // pre-formatted plain text!
    });

    test('should split and chunk summary when plain text body exceeds 2KB', () async {
      // Build a huge body to trigger chunking (> 2000 characters)
      final hugeBodyBuffer = StringBuffer();
      for (var i = 0; i < 300; i++) {
        hugeBodyBuffer.writeln('- Huge bullet point index number $i');
      }
      aiService.customBody = hugeBodyBuffer.toString();

      final watchUpload = {
        'COMMAND': 1,
        'RAW_TEXT': 'Trigger chunking',
        'NOTE_ID': 9999,
        'MSG_ID': 3,
        'SESSION_ID': newSessionId,
      };

      await pebbleService.handleWatchMessage(watchUpload);

      // Check sent messages
      // First: COMMAND=10 (Summarizing...)
      // Second: COMMAND=10 (Title of completed note)
      // Next: Multiple COMMAND=11 (Chunks)
      // Last: COMMAND=12 (Complete)
      expect(sentMessages.length, greaterThan(3));
      expect(sentMessages[0]['COMMAND'], equals(10)); // Summarizing...
      expect(sentMessages[1]['COMMAND'], equals(10)); // Real Title
      expect(sentMessages[2]['COMMAND'], equals(11)); // Chunk 0
      expect(sentMessages[2]['CHUNK_INDEX'], equals(0));
      expect(sentMessages[2]['CHUNK_TOTAL'], greaterThan(1));
      
      expect(sentMessages.last['COMMAND'], equals(12)); // Complete
      expect(sentMessages.last['COMPLETE'], equals(1));
    });

    test('should send CHUNK_RESET (COMMAND=13) to watch if AI summarization fails', () async {
      aiService.failNext = true;

      final watchUpload = {
        'COMMAND': 1,
        'RAW_TEXT': 'Failing note',
        'NOTE_ID': 5555,
        'MSG_ID': 4,
        'SESSION_ID': newSessionId,
      };

      await pebbleService.handleWatchMessage(watchUpload);

      // Verify Drift DB status was updated to failed
      final notes = await database.getAllNotes();
      expect(notes.length, equals(1));
      expect(notes.first.processingStatus, equals('failed'));

      // Check messages:
      // First: COMMAND=10 (Summarizing...)
      // Second: COMMAND=13 (CHUNK_RESET/Abort)
      expect(sentMessages.length, equals(2));
      expect(sentMessages[0]['COMMAND'], equals(10));
      expect(sentMessages[1]['COMMAND'], equals(13));
    });

    test('should return note from DB on note fetch request (COMMAND=2)', () async {
      // Pre-populate note in database
      await database.insertNote(NotesCompanion.insert(
        watchId: const drift.Value(8888),
        rawText: 'Fetched transcript',
        summaryTitle: const drift.Value('Pre-existing Title'),
        bodyPlainText: const drift.Value('• Point A\n• Point B'),
        processingStatus: const drift.Value('completed'),
      ));

      final fetchRequest = {
        'COMMAND': 2,
        'NOTE_ID': 8888,
        'MSG_ID': 5,
        'SESSION_ID': newSessionId,
      };

      await pebbleService.handleWatchMessage(fetchRequest);

      expect(sentMessages.length, equals(1));
      expect(sentMessages[0]['COMMAND'], equals(14));
      expect(sentMessages[0]['TITLE'], equals('Pre-existing Title'));
      expect(sentMessages[0]['BODY'], equals('• Point A\n• Point B'));
    });
  });
}
