import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gemini_nano_android/gemini_nano_android.dart';
import 'parser.dart';

class SummaryResult {
  final String title;
  final String body;
  final String provider;

  SummaryResult({
    required this.title,
    required this.body,
    required this.provider,
  });
}

abstract class AIService {
  Future<SummaryResult> summarize(String rawText);
  Future<bool> isAvailable();
}

class GeminiNanoService implements AIService {
  final _nano = GeminiNanoAndroid();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _nano.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SummaryResult> summarize(String rawText) async {
    final prompt = "${AIParser.systemPrompt}\n\nTranscript: \"\"\"$rawText\"\"\"";
    final results = await _nano.generate(
      prompt: prompt,
      maxOutputTokens: 256,
    );
    if (results.isEmpty) {
      throw Exception("Gemini Nano returned empty response");
    }
    final text = results.first;
    final parsed = AIParser.parseAIResponse(text);
    return SummaryResult(
      title: parsed['title']!,
      body: parsed['body']!,
      provider: 'nano',
    );
  }
}

class CloudAIService implements AIService {
  final _secureStorage = const FlutterSecureStorage();

  @override
  Future<bool> isAvailable() async {
    final key = await _secureStorage.read(key: 'cloud_api_key');
    return key != null && key.trim().isNotEmpty;
  }

  @override
  Future<SummaryResult> summarize(String rawText) async {
    final provider = await _secureStorage.read(key: 'cloud_provider') ?? 'openai';
    final apiKey = await _secureStorage.read(key: 'cloud_api_key');
    final modelId = await _secureStorage.read(key: 'cloud_model_id');
    final baseUrl = await _secureStorage.read(key: 'cloud_base_url');

    if (apiKey == null || apiKey.trim().isEmpty) {
      throw Exception("API key is not configured");
    }

    switch (provider) {
      case 'anthropic':
        return _summarizeAnthropic(rawText, apiKey, modelId ?? 'claude-3-5-sonnet-20240620');
      case 'google':
        return _summarizeGoogleGemini(rawText, apiKey, modelId ?? 'gemini-1.5-flash');
      case 'openai':
      case 'openrouter':
      case 'opencode_zen':
      case 'opencode_go':
      case 'custom':
      default:
        return _summarizeOpenAICompatible(
          rawText: rawText,
          apiKey: apiKey,
          provider: provider,
          modelId: modelId,
          customUrl: baseUrl,
        );
    }
  }

  Future<SummaryResult> _summarizeOpenAICompatible({
    required String rawText,
    required String apiKey,
    required String provider,
    String? modelId,
    String? customUrl,
  }) async {
    String url = 'https://api.openai.com/v1/chat/completions';
    String model = modelId ?? 'gpt-4o-mini';

    if (provider == 'openrouter') {
      url = 'https://openrouter.ai/api/v1/chat/completions';
      model = modelId ?? 'google/gemini-flash-1.5';
    } else if (provider == 'opencode_zen') {
      url = customUrl ?? 'https://api.opencode.zen/v1/chat/completions';
      model = modelId ?? 'opencode-zen-model';
    } else if (provider == 'opencode_go') {
      url = customUrl ?? 'https://api.opencode.go/v1/chat/completions';
      model = modelId ?? 'opencode-go-model';
    } else if (provider == 'custom') {
      if (customUrl == null || customUrl.isEmpty) {
        throw Exception("Custom Base URL is not configured");
      }
      url = customUrl;
      model = modelId ?? 'custom-model';
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    final body = json.encode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': AIParser.systemPrompt},
        {'role': 'user', 'content': 'Transcript: """$rawText"""'}
      ],
      'temperature': 0.2,
    });

    final response = await http.post(Uri.parse(url), headers: headers, body: body);
    if (response.statusCode != 200) {
      throw Exception("Cloud API Error [${response.statusCode}]: ${response.body}");
    }

    final data = json.decode(response.body);
    final text = data['choices'][0]['message']['content']?.toString() ?? '';
    final parsed = AIParser.parseAIResponse(text);

    return SummaryResult(
      title: parsed['title']!,
      body: parsed['body']!,
      provider: provider,
    );
  }

  Future<SummaryResult> _summarizeAnthropic(String rawText, String apiKey, String model) async {
    const url = 'https://api.anthropic.com/v1/messages';
    final headers = {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    };

    final body = json.encode({
      'model': model,
      'system': AIParser.systemPrompt,
      'messages': [
        {'role': 'user', 'content': 'Transcript: """$rawText"""'}
      ],
      'max_tokens': 512,
      'temperature': 0.2,
    });

    final response = await http.post(Uri.parse(url), headers: headers, body: body);
    if (response.statusCode != 200) {
      throw Exception("Anthropic API Error [${response.statusCode}]: ${response.body}");
    }

    final data = json.decode(response.body);
    final text = data['content'][0]['text']?.toString() ?? '';
    final parsed = AIParser.parseAIResponse(text);

    return SummaryResult(
      title: parsed['title']!,
      body: parsed['body']!,
      provider: 'anthropic',
    );
  }

  Future<SummaryResult> _summarizeGoogleGemini(String rawText, String apiKey, String model) async {
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';
    final headers = {
      'Content-Type': 'application/json',
    };

    final body = json.encode({
      'contents': [
        {
          'parts': [
            {'text': "System instructions: ${AIParser.systemPrompt}\n\nTranscript: \"\"\"$rawText\"\"\""}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 512,
      }
    });

    final response = await http.post(Uri.parse(url), headers: headers, body: body);
    if (response.statusCode != 200) {
      throw Exception("Google Gemini Cloud Error [${response.statusCode}]: ${response.body}");
    }

    final data = json.decode(response.body);
    final text = data['candidates'][0]['content']['parts'][0]['text']?.toString() ?? '';
    final parsed = AIParser.parseAIResponse(text);

    return SummaryResult(
      title: parsed['title']!,
      body: parsed['body']!,
      provider: 'google',
    );
  }
}

class AIServiceRouter implements AIService {
  final GeminiNanoService _nanoService = GeminiNanoService();
  final CloudAIService _cloudService = CloudAIService();
  final _secureStorage = const FlutterSecureStorage();

  @override
  Future<bool> isAvailable() async {
    final mode = await _secureStorage.read(key: 'ai_mode') ?? 'auto';
    if (mode == 'nano') {
      return await _nanoService.isAvailable();
    } else if (mode == 'cloud') {
      return await _cloudService.isAvailable();
    } else {
      // Auto mode: check if either is available
      return await _nanoService.isAvailable() || await _cloudService.isAvailable();
    }
  }

  @override
  Future<SummaryResult> summarize(String rawText) async {
    final mode = await _secureStorage.read(key: 'ai_mode') ?? 'auto';

    if (mode == 'nano') {
      if (await _nanoService.isAvailable()) {
        return await _nanoService.summarize(rawText).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw Exception("Gemini Nano timed out"),
        );
      }
      throw Exception("Gemini Nano is not available on this device");
    }

    if (mode == 'cloud') {
      return await _cloudService.summarize(rawText);
    }

    // Auto mode fallback tree
    if (await _nanoService.isAvailable()) {
      try {
        return await _nanoService.summarize(rawText).timeout(
          const Duration(seconds: 8),
        );
      } catch (_) {
        // Fallback to cloud if nano fails or times out
        if (await _cloudService.isAvailable()) {
          return await _cloudService.summarize(rawText);
        }
        rethrow;
      }
    }

    // Nano unavailable, use cloud
    return await _cloudService.summarize(rawText);
  }
}
