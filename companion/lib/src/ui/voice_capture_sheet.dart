import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/database.dart';
import '../ai/ai_service.dart';
import '../ai/parser.dart';
import '../pebble/speech_service.dart';
import 'package:drift/drift.dart' as drift;

class VoiceCaptureSheet extends StatefulWidget {
  const VoiceCaptureSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const VoiceCaptureSheet(),
    );
  }

  @override
  State<VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<VoiceCaptureSheet> with SingleTickerProviderStateMixin {
  final PhoneSpeechService _speechService = PhoneSpeechService();
  String _transcription = '';
  double _soundLevel = 0.0;
  bool _isListening = false;
  bool _isSummarizing = false;
  String? _errorMessage;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkPermissionAndStart();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speechService.cancelListening();
    super.dispose();
  }

  Future<void> _checkPermissionAndStart() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      _startListening();
    } else {
      setState(() {
        _errorMessage = 'Microphone permission is required for voice capture.';
      });
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _errorMessage = null;
      _isListening = true;
    });

    try {
      await _speechService.startListening(
        onResult: (words) {
          if (mounted) {
            setState(() {
              _transcription = words;
            });
          }
        },
        onSoundLevel: (level) {
          if (mounted) {
            setState(() {
              _soundLevel = level;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechService.stopListening();
      setState(() {
        _isListening = false;
      });
    } else {
      _startListening();
    }
  }

  Future<void> _cancelRecording() async {
    await _speechService.cancelListening();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _commitRecording() async {
    if (_transcription.trim().isEmpty) {
      setState(() {
        _errorMessage = "No speech detected. Please try speaking again.";
      });
      return;
    }

    await _speechService.stopListening();

    setState(() {
      _isListening = false;
      _isSummarizing = true;
      _errorMessage = null;
    });

    final database = Provider.of<AppDatabase>(context, listen: false);
    final aiService = Provider.of<AIService>(context, listen: false);

    int? dbId;
    try {
      // 1. Insert note into database
      final companion = NotesCompanion.insert(
        watchId: const drift.Value(null), // Phone-captured note!
        createdAt: drift.Value(DateTime.now()),
        rawText: _transcription,
        processingStatus: const drift.Value('processing'),
      );
      dbId = await database.insertNote(companion);

      // 2. Perform AI Summarization
      final result = await aiService.summarize(_transcription);
      final plainTextBody = AIParser.convertMarkdownToPlainText(result.body);

      // 3. Update DB
      final originalNote = await database.getNoteById(dbId);
      if (originalNote != null) {
        await database.updateNoteEntry(originalNote.copyWith(
          summaryTitle: drift.Value(result.title),
          summaryBody: drift.Value(result.body),
          bodyPlainText: drift.Value(plainTextBody),
          aiProvider: drift.Value(result.provider),
          processingStatus: 'completed',
        ));
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print("Native voice capture summarization failed: $e");
      
      // Update note in database to failed
      if (dbId != null) {
        final originalNote = await database.getNoteById(dbId);
        if (originalNote != null) {
          await database.updateNoteEntry(originalNote.copyWith(
            processingStatus: 'failed',
            summaryTitle: const drift.Value('AI Summarization Failed'),
            summaryBody: drift.Value('Failed to summarize transcript: $e'),
            bodyPlainText: drift.Value('Failed to summarize transcript: $e'),
          ));
        }
      }

      if (mounted) {
        setState(() {
          _isSummarizing = false;
          _errorMessage = 'AI Summarization failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.85,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Dark slate
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Stack(
        children: [
          // Background Gradient decoration
          Positioned(
            top: -150,
            left: -150,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.08),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF818CF8).withOpacity(0.08),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Handle Drag bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (_isSummarizing)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: Color(0xFF6366F1),
                            strokeWidth: 3.0,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Synthesizing thought...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Running AI model to generate bullet points...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Voice Memo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (_isListening)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF10B981).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.fiber_manual_record, color: Color(0xFF10B981), size: 10),
                              SizedBox(width: 6),
                              Text(
                                'REC',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Real-time Visualizer & Pulsing microphone
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Sound wave visualizer rings
                          ..._buildVisualizerRings(),

                          // Microphone circle button
                          ScaleTransition(
                            scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                            child: Material(
                              shape: const CircleBorder(),
                              color: _isListening
                                  ? const Color(0xFF6366F1)
                                  : Colors.blueGrey.withOpacity(0.2),
                              elevation: _isListening ? 8 : 0,
                              child: InkWell(
                                onTap: _toggleListening,
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 90,
                                  height: 90,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    _isListening ? Icons.mic : Icons.mic_none,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Real-time Transcription screen box
                  Expanded(
                    flex: 6,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B), // Dark slate cards
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.text_fields_outlined, color: Colors.blueGrey.withOpacity(0.6), size: 14),
                              const SizedBox(width: 8),
                              Text(
                                'REAL-TIME TRANSCRIPTION',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              reverse: true,
                              child: Text(
                                _transcription.isEmpty
                                    ? 'Start speaking, your transcript will appear here in real-time...'
                                    : _transcription,
                                style: TextStyle(
                                  color: _transcription.isEmpty
                                      ? Colors.white.withOpacity(0.3)
                                      : Colors.white,
                                  fontSize: 14,
                                  height: 1.5,
                                  fontStyle: _transcription.isEmpty ? FontStyle.italic : FontStyle.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Error notification text
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Action Row Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Cancel Button
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blueGrey,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _cancelRecording,
                      ),

                      // Commit Done Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1), // Indigo accent
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _transcription.isEmpty ? null : _commitRecording,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildVisualizerRings() {
    if (!_isListening) return [];

    // Map decibels to scale multiplier
    // Level comes in from 0.0 to 10.0+ typically
    final scaleFactor = 1.0 + (_soundLevel.clamp(0.0, 10.0) / 10.0) * 0.6;

    return [
      AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value * scaleFactor,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withOpacity(0.03),
                border: Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
          );
        },
      ),
      AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value * (scaleFactor * 0.8),
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withOpacity(0.06),
                border: Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
          );
        },
      ),
    ];
  }
}
