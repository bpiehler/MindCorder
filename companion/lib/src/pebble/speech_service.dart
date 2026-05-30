import 'package:speech_to_text/speech_to_text.dart';

class PhoneSpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) => print('SpeechToText Error: $val'),
        onStatus: (val) => print('SpeechToText Status: $val'),
      );
      return _isInitialized;
    } catch (e) {
      print('SpeechToText Initialization Exception: $e');
      return false;
    }
  }

  bool get isListening => _speech.isListening;

  Future<void> startListening({
    required Function(String words) onResult,
    required Function(double level) onSoundLevel,
  }) async {
    final available = await initialize();
    if (!available) {
      throw Exception("Speech recognition is not available on this device.");
    }

    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
      },
      onSoundLevelChange: onSoundLevel,
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 15),
      partialResults: true,
      listenMode: ListenMode.dictation,
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  Future<void> cancelListening() async {
    await _speech.cancel();
  }
}
