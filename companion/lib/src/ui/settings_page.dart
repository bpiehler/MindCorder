import 'package:flutter/material';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../ai/ai_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _secureStorage = const FlutterSecureStorage();
  
  String _aiMode = 'auto'; // auto, nano, cloud
  String _provider = 'openai'; // openai, anthropic, google, openrouter, custom, opencode_zen, opencode_go
  final _apiKeyController = TextEditingController();
  final _modelIdController = TextEditingController();
  final _baseUrlController = TextEditingController();
  
  bool _obscureApiKey = true;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final aiMode = await _secureStorage.read(key: 'ai_mode') ?? 'auto';
    final provider = await _secureStorage.read(key: 'cloud_provider') ?? 'openai';
    final apiKey = await _secureStorage.read(key: 'cloud_api_key') ?? '';
    final modelId = await _secureStorage.read(key: 'cloud_model_id') ?? '';
    final baseUrl = await _secureStorage.read(key: 'cloud_base_url') ?? '';

    setState(() {
      _aiMode = aiMode;
      _provider = provider;
      _apiKeyController.text = apiKey;
      _modelIdController.text = modelId;
      _baseUrlController.text = baseUrl;
    });
  }

  Future<void> _saveSettings() async {
    await _secureStorage.write(key: 'ai_mode', value: _aiMode);
    await _secureStorage.write(key: 'cloud_provider', value: _provider);
    await _secureStorage.write(key: 'cloud_api_key', value: _apiKeyController.text.trim());
    await _secureStorage.write(key: 'cloud_model_id', value: _modelIdController.text.trim());
    await _secureStorage.write(key: 'cloud_base_url', value: _baseUrlController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: Colors.emerald,
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    // Momentarily save settings to secure storage for testing
    await _secureStorage.write(key: 'cloud_provider', value: _provider);
    await _secureStorage.write(key: 'cloud_api_key', value: _apiKeyController.text.trim());
    await _secureStorage.write(key: 'cloud_model_id', value: _modelIdController.text.trim());
    await _secureStorage.write(key: 'cloud_base_url', value: _baseUrlController.text.trim());

    try {
      final cloudService = CloudAIService();
      final result = await cloudService.summarize("Meeting note: brief test transcription stream to check connection.");
      
      setState(() {
        _testSuccess = true;
        _testResult = "Connection Successful! Model returned: \"${result.title}\"";
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = "Connection Failed: $e";
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCloudFields = _aiMode == 'cloud' || _aiMode == 'auto';
    final showCustomUrl = _provider == 'custom' || _provider == 'opencode_zen' || _provider == 'opencode_go';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.emerald),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI SUMMARIZATION ROUTER',
              style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _aiMode,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(border: InputBorder.none),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto (On-Device ➔ Cloud Fallback)')),
                    DropdownMenuItem(value: 'nano', child: Text('On-Device Only (Free / Gemini Nano)')),
                    DropdownMenuItem(value: 'cloud', child: Text('Cloud Only (BYOK Keys)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _aiMode = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (showCloudFields) ...[
              const Text(
                'CLOUD API CONFIGURATION (BYOK)',
                style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Provider Select
                      DropdownButtonFormField<String>(
                        value: _provider,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Provider',
                          labelStyle: TextStyle(color: Colors.blueGrey),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                          DropdownMenuItem(value: 'anthropic', child: Text('Anthropic (Claude)')),
                          DropdownMenuItem(value: 'google', child: Text('Google Gemini Cloud')),
                          DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
                          DropdownMenuItem(value: 'opencode_zen', child: Text('OpenCode Zen')),
                          DropdownMenuItem(value: 'opencode_go', child: Text('OpenCode Go')),
                          DropdownMenuItem(value: 'custom', child: Text('Custom Endpoint')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _provider = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      // API Key
                      TextField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          labelStyle: const TextStyle(color: Colors.blueGrey),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, color: Colors.blueGrey),
                            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Model ID
                      TextField(
                        controller: _modelIdController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Model ID (Optional)',
                          hintText: 'e.g. gpt-4o-mini',
                          hintStyle: TextStyle(color: Colors.blueGrey, fontSize: 12),
                          labelStyle: TextStyle(color: Colors.blueGrey),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                        ),
                      ),
                      if (showCustomUrl) ...[
                        const SizedBox(height: 16),
                        // Base URL
                        TextField(
                          controller: _baseUrlController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Base URL / Endpoint',
                            hintText: 'e.g. https://api.openai.com/v1/chat/completions',
                            hintStyle: TextStyle(color: Colors.blueGrey, fontSize: 11),
                            labelStyle: TextStyle(color: Colors.blueGrey),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Connection Test section
              if (_testResult != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testSuccess ? Colors.emerald.withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _testSuccess ? Colors.emerald.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testSuccess ? Colors.emerald : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF334155)),
                  ),
                ).build(
                  context,
                  onPressed: _isTesting ? null : _testConnection,
                  child: _isTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.indigoAccent, strokeWidth: 2),
                        )
                      : const Text(
                          'Test API Connection',
                          style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
            const SizedBox(height: 40),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: _saveSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Add simple extension to support flat button implementation in standard ElevatedButton
extension on ButtonStyle {
  Widget build(BuildContext context, {required VoidCallback? onPressed, required Widget child}) {
    return ElevatedButton(
      style: this,
      onPressed: onPressed,
      child: child,
    );
  }
}
