import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../data/database.dart';
import '../pebble/pebble_service.dart';
import 'package:drift/drift.dart' as drift;
import 'voice_capture_sheet.dart';

class NoteListPage extends StatefulWidget {
  const NoteListPage({super.key});

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  bool _isWatchConnected = false;
  late final Stream<List<Note>> _notesStream;

  @override
  void initState() {
    super.initState();
    _notesStream = Provider.of<AppDatabase>(context, listen: false).watchAllNotes();
    _checkWatchConnection();
    // Periodically update watch connection status
    Stream.periodic(const Duration(seconds: 4)).listen((_) {
      if (mounted) {
        _checkWatchConnection();
      }
    });
  }

  Future<void> _checkWatchConnection() async {
    final pebbleService = Provider.of<PebbleService>(context, listen: false);
    final connected = await pebbleService.isWatchConnected();
    if (mounted) {
      setState(() {
        _isWatchConnected = connected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final database = Provider.of<AppDatabase>(context);
    final pebbleService = Provider.of<PebbleService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate background
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'MindCorder',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 10),
            // Connection Dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isWatchConnected ? const Color(0xFF10B981) : Colors.blueGrey,
                boxShadow: _isWatchConnected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.5),
                          spreadRadius: 2,
                          blurRadius: 4,
                        )
                      ]
                    : [],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _isWatchConnected ? 'Pebble Connected' : 'Watch Offline',
              style: TextStyle(
                fontSize: 10,
                color: _isWatchConnected ? const Color(0xFF10B981) : Colors.blueGrey,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.blueGrey),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: StreamBuilder<List<Note>>(
        stream: _notesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.indigoAccent),
            );
          }
          final notes = snapshot.data ?? [];

          if (notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mic_none,
                    size: 64,
                    color: Colors.blueGrey.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Zero-Friction thought capturing',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start dictating from your Pebble watch!',
                    style: TextStyle(
                      color: Colors.blueGrey.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return _buildNoteCard(context, note, database);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF6366F1), // Indigo accent
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => _showAddOptionsSheet(context),
      ),
    );
  }

  Widget _buildNoteCard(BuildContext context, Note note, AppDatabase database) {
    final title = note.summaryTitle ?? 'Processing note...';
    final hasFailed = note.processingStatus == 'failed';
    final isProcessing = note.processingStatus == 'processing';

    return Dismissible(
      key: Key(note.id.toString()),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.archive, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        database.updateNoteEntry(note.copyWith(isArchived: true));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Note "${note.summaryTitle ?? "Untitled"}" archived'),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      },
      child: Card(
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: note.isPinned
                ? const Color(0xFF6366F1).withOpacity(0.5)
                : Colors.transparent,
            width: 1,
          ),
        ),
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Row(
            children: [
              if (note.isPinned) ...[
                const Icon(Icons.push_pin, color: Color(0xFF6366F1), size: 16),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: hasFailed ? Colors.redAccent : Colors.white,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildStatusBadge(note.processingStatus),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                note.rawText,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDateTime(note.createdAt),
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 11,
                    ),
                  ),
                  if (note.aiProvider != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        note.aiProvider!.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF818CF8),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          onTap: () {
            if (!isProcessing) {
              context.push('/detail/${note.id}');
            }
          },
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    IconData? icon;

    switch (status) {
      case 'processing':
        color = Colors.blueAccent;
        label = 'AI PROCESSING';
        break;
      case 'failed':
        color = Colors.redAccent;
        label = 'FAILED';
        icon = Icons.error_outline;
        break;
      case 'pending_foreground':
        color = Colors.amber;
        label = 'QUEUED FOR APP';
        icon = Icons.hourglass_empty;
        break;
      case 'completed':
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 10),
            const SizedBox(width: 4),
          ],
          if (status == 'processing') ...[
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showAddNoteDialog(BuildContext context, AppDatabase database, PebbleService pebbleService) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Add Audio Transcript', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type or paste a messy transcript stream here...',
              hintStyle: TextStyle(color: Colors.blueGrey.withOpacity(0.6)),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF6366F1)),
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
              child: const Text('Summarize', style: TextStyle(color: Colors.white)),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  // Simulate watch upload
                  final watchId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                  pebbleService.handleWatchMessage({
                    'COMMAND': 1,
                    'RAW_TEXT': text,
                    'NOTE_ID': watchId,
                    'MSG_ID': 999,
                    'SESSION_ID': DateTime.now().millisecondsSinceEpoch,
                  });
                }
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _showAddOptionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B), // Dark slate
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Capture Thought',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Color(0xFF6366F1)),
                ),
                title: const Text('Record Voice Memo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Dictate and translate audio stream in real-time', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  VoiceCaptureSheet.show(context);
                },
              ),
              const Divider(color: Color(0xFF334155), indent: 16, endIndent: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Colors.tealAccent),
                ),
                title: const Text('Write Text Memo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Type or paste custom transcript manually', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  final database = Provider.of<AppDatabase>(context, listen: false);
                  final pebbleService = Provider.of<PebbleService>(context, listen: false);
                  _showAddNoteDialog(context, database, pebbleService);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
