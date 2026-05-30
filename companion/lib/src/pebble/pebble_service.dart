import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:drift/drift.dart';
import '../data/database.dart';
import '../ai/ai_service.dart';
import '../ai/parser.dart';

class PebbleService with WidgetsBindingObserver {
  static const _methodChannel = MethodChannel('mindcorder/pebble_methods');
  static const _eventChannel = EventChannel('mindcorder/pebble_events');

  final AppDatabase database;
  final AIService aiService;

  int _sessionId = DateTime.now().millisecondsSinceEpoch;
  int _outgoingMsgId = 1000;
  int _lastProcessedNoteId = 0;

  StreamSubscription? _eventSubscription;

  PebbleService({
    required this.database,
    required this.aiService,
  });

  /// Starts listening to Pebble watch messages.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final castedEvent = Map<String, dynamic>.from(event);
          handleWatchMessage(castedEvent);
        }
      },
      onError: (err) {
        print("Pebble EventChannel Error: $err");
      },
    );
  }

  /// Stops listening to watch messages.
  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
  }

  Future<bool> isWatchConnected() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isWatchConnected') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> startWatchApp() async {
    try {
      await _methodChannel.invokeMethod('startAppOnWatch');
    } catch (_) {}
  }

  Future<void> stopWatchApp() async {
    try {
      await _methodChannel.invokeMethod('stopAppOnWatch');
    } catch (_) {}
  }

  Future<void> sendMapToWatch(Map<String, dynamic> data) async {
    try {
      await _methodChannel.invokeMethod('sendToWatch', data);
    } catch (e) {
      print("Failed to send message to Pebble: $e");
    }
  }

  Future<void> handleWatchMessage(Map<String, dynamic> msg) async {
    final command = msg['COMMAND'] as int?;
    final msgId = msg['MSG_ID'] as int?;
    final incomingSessionId = msg['SESSION_ID'] as int?;

    print("Received Command $command with msgId $msgId from Watch");

    if (command == null) return;

    // Acknowledge session changes
    if (incomingSessionId != null && incomingSessionId > _sessionId) {
      _sessionId = incomingSessionId;
    }

    switch (command) {
      case 0:
        // Handshake protocol initiation
        print("Handshake received from Watch. Sending Handshake ACK.");
        await sendMapToWatch({
          'COMMAND': 0,
          'SESSION_ID': _sessionId,
          'MSG_ID': _outgoingMsgId++,
        });
        break;

      case 1:
        // New dictation transcript upload
        final rawText = msg['RAW_TEXT'] as String?;
        final noteId = msg['NOTE_ID'] as int?;

        if (rawText == null || noteId == null) return;
        if (noteId == _lastProcessedNoteId) {
          print("Duplicate Note ID $noteId detected. Dropping.");
          return;
        }
        _lastProcessedNoteId = noteId;

        await _processNewNoteDictation(rawText, noteId);
        break;

      case 2:
        // Fetch full note body request
        final noteId = msg['NOTE_ID'] as int?;
        if (noteId == null) return;
        await _handleFetchNoteRequest(noteId);
        break;
    }
  }

  Future<void> _processNewNoteDictation(String rawText, int watchId) async {
    // 1. Write the raw note to the Drift DB
    final companion = NotesCompanion.insert(
      watchId: Value(watchId),
      createdAt: Value(DateTime.now()),
      rawText: rawText,
      processingStatus: const Value('processing'),
    );
    final dbId = await database.insertNote(companion);

    // 2. Notify the watch that we are summarizing
    await sendMapToWatch({
      'COMMAND': 10, // Summary Title
      'TITLE': 'Summarizing...',
      'SESSION_ID': _sessionId,
      'MSG_ID': _outgoingMsgId++,
    });

    try {
      // 3. Summarize raw text
      final result = await aiService.summarize(rawText);

      // 4. Pre-format for Pebble OS
      final plainTextBody = AIParser.convertMarkdownToPlainText(result.body);

      // 5. Update DB
      final originalNote = await database.getNoteById(dbId);
      if (originalNote != null) {
        await database.updateNoteEntry(originalNote.copyWith(
          summaryTitle: Value(result.title),
          summaryBody: Value(result.body),
          bodyPlainText: Value(plainTextBody),
          aiProvider: Value(result.provider),
          processingStatus: 'completed',
        ));
      }

      // 6. Push the completed summary to the watch
      await _sendSummaryToWatch(result.title, plainTextBody);

    } catch (e) {
      print("AI Summarization failed: $e");
      
      String errorTitle = 'AI Error';
      String errorBody = 'Summarization failed: $e';
      bool isBgError = false;
      
      if (e.toString().contains('Background usage is blocked') || 
          e.toString().contains('ErrorCode 30')) {
        errorTitle = 'BG Blocked';
        errorBody = 'Local Gemini Nano cannot run in the background. '
            'Please open the companion app on your phone to kick off summarization, '
            'or configure a Cloud API Key (OpenAI, Anthropic, or Gemini Cloud) in Settings '
            'for seamless background processing!';
        isBgError = true;
      } else if (e.toString().contains('TimeoutException') || 
                 e.toString().contains('timed out')) {
        errorTitle = 'Timeout';
        errorBody = 'The summarization request timed out. '
            'Please try again, or configure a Cloud API Key in Settings for faster responses!';
      }
      
      // Update DB
      final originalNote = await database.getNoteById(dbId);
      if (originalNote != null) {
        await database.updateNoteEntry(originalNote.copyWith(
          processingStatus: isBgError ? 'pending_foreground' : 'failed',
          summaryTitle: Value(errorTitle),
          summaryBody: Value(errorBody),
          bodyPlainText: Value(errorBody),
        ));
      }

      // Send the error message directly to the watch so the user is informed
      try {
        await _sendSummaryToWatch(errorTitle, errorBody);
      } catch (sendError) {
        print("Failed to send error notification to watch: $sendError");
        // Fallback to sending CHUNK_RESET in case of communication failure
        await sendMapToWatch({
          'COMMAND': 13, // CHUNK_RESET
          'SESSION_ID': _sessionId,
          'MSG_ID': _outgoingMsgId++,
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("App resumed: processing pending foreground notes");
      _processPendingForegroundNotes();
    }
  }

  bool _isProcessingPending = false;

  Future<void> _processPendingForegroundNotes() async {
    if (_isProcessingPending) return;
    _isProcessingPending = true;

    try {
      final pendingNotes = await (database.select(database.notes)
            ..where((t) => t.processingStatus.equals('pending_foreground')))
          .get();

      if (pendingNotes.isEmpty) return;

      print("Found ${pendingNotes.length} pending foreground notes to summarize");

      for (final note in pendingNotes) {
        final currentNote = await database.getNoteById(note.id);
        if (currentNote == null || currentNote.processingStatus != 'pending_foreground') {
          continue;
        }

        await database.updateNoteEntry(currentNote.copyWith(
          processingStatus: 'processing',
        ));

        try {
          print("Summarizing note ${note.id} in foreground...");
          final result = await aiService.summarize(note.rawText);
          final plainTextBody = AIParser.convertMarkdownToPlainText(result.body);

          await database.updateNoteEntry(currentNote.copyWith(
            summaryTitle: Value(result.title),
            summaryBody: Value(result.body),
            bodyPlainText: Value(plainTextBody),
            aiProvider: Value(result.provider),
            processingStatus: 'completed',
          ));

          print("Successfully summarized note ${note.id} in foreground!");

          if (note.watchId != null) {
            await _sendSummaryToWatch(result.title, plainTextBody);
          }
        } catch (e) {
          print("Foreground summarization failed for note ${note.id}: $e");
          
          final isBgError = e.toString().contains('Background usage is blocked') || 
                            e.toString().contains('ErrorCode 30');
          
          await database.updateNoteEntry(currentNote.copyWith(
            processingStatus: isBgError ? 'pending_foreground' : 'failed',
            summaryTitle: Value(isBgError ? 'BG Blocked' : 'AI Error'),
            summaryBody: Value(isBgError ? 'Local Gemini Nano cannot run in the background.' : 'Summarization failed: $e'),
            bodyPlainText: Value(isBgError ? 'Local Gemini Nano cannot run in the background.' : 'Summarization failed: $e'),
          ));
        }
      }
    } finally {
      _isProcessingPending = false;
    }
  }

  Future<void> retrySummarization(int noteId) async {
    final note = await database.getNoteById(noteId);
    if (note == null) return;

    await database.updateNoteEntry(note.copyWith(
      processingStatus: 'processing',
    ));

    try {
      print("Retrying summarization for note $noteId...");
      final result = await aiService.summarize(note.rawText);
      final plainTextBody = AIParser.convertMarkdownToPlainText(result.body);

      await database.updateNoteEntry(note.copyWith(
        summaryTitle: Value(result.title),
        summaryBody: Value(result.body),
        bodyPlainText: Value(plainTextBody),
        aiProvider: Value(result.provider),
        processingStatus: 'completed',
      ));

      print("Successfully retried summarization for note $noteId!");

      if (note.watchId != null) {
        await _sendSummaryToWatch(result.title, plainTextBody);
      }
    } catch (e) {
      print("Retry summarization failed for note $noteId: $e");
      
      final isBgError = e.toString().contains('Background usage is blocked') || 
                        e.toString().contains('ErrorCode 30');
      
      await database.updateNoteEntry(note.copyWith(
        processingStatus: isBgError ? 'pending_foreground' : 'failed',
        summaryTitle: Value(isBgError ? 'BG Blocked' : 'AI Error'),
        summaryBody: Value(isBgError ? 'Local Gemini Nano cannot run in the background.' : 'Summarization failed: $e'),
        bodyPlainText: Value(isBgError ? 'Local Gemini Nano cannot run in the background.' : 'Summarization failed: $e'),
      ));
      
      rethrow;
    }
  }

  Future<void> _handleFetchNoteRequest(int watchId) async {
    final note = await database.getNoteByWatchId(watchId);
    if (note == null) {
      // Return not found
      await _sendSummaryToWatch('Not Found', 'The requested note could not be found.');
      return;
    }

    final title = note.summaryTitle ?? 'Untitled';
    final body = note.bodyPlainText ?? note.summaryBody ?? 'No content';
    await _sendSummaryToWatch(title, body);
  }

  Future<void> _sendSummaryToWatch(String title, String bodyPlainText) async {
    final totalChars = bodyPlainText.length;

    // Standard AppMessage maximum text buffer chunk size is 2KB.
    // 500 characters is extremely safe and will never exceed 2KB (even with 4-byte UTF-8 emojis/characters),
    // while preventing any multi-byte character boundary splitting!
    const maxChunkSize = 500; 

    if (totalChars <= maxChunkSize) {
      // Small payload: send in a single COMMAND=14 packet
      await sendMapToWatch({
        'COMMAND': 14,
        'TITLE': title,
        'BODY': bodyPlainText,
        'SESSION_ID': _sessionId,
        'MSG_ID': _outgoingMsgId++,
      });
    } else {
      // Large payload: split into chunks by character boundaries and send via sequential COMMAND=11 packets
      final chunks = <String>[];
      for (var i = 0; i < totalChars; i += maxChunkSize) {
        final end = (i + maxChunkSize < totalChars) ? i + maxChunkSize : totalChars;
        chunks.add(bodyPlainText.substring(i, end));
      }

      final chunkTotal = chunks.length;

      // Send the summary title first to update watch UI state
      await sendMapToWatch({
        'COMMAND': 10,
        'TITLE': title,
        'SESSION_ID': _sessionId,
        'MSG_ID': _outgoingMsgId++,
      });

      // Send each chunk sequentially
      for (var index = 0; index < chunkTotal; index++) {
        await sendMapToWatch({
          'COMMAND': 11,
          'SUMMARY_CHUNK': chunks[index],
          'CHUNK_INDEX': index,
          'CHUNK_TOTAL': chunkTotal,
          'SESSION_ID': _sessionId,
          'MSG_ID': _outgoingMsgId++,
        });
        
        // Minor delay to prevent message buffer choke on high-throughput transfers
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Send completed packet signal
      await sendMapToWatch({
        'COMMAND': 12,
        'COMPLETE': 1,
        'SESSION_ID': _sessionId,
        'MSG_ID': _outgoingMsgId++,
      });
    }
  }
}
