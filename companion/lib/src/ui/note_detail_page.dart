import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../data/database.dart';
import '../pebble/pebble_service.dart';

class NoteDetailPage extends StatefulWidget {
  final int noteId;

  const NoteDetailPage({super.key, required this.noteId});

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  bool _isRawTranscriptExpanded = false;
  bool _isRetrying = false;

  @override
  Widget build(BuildContext context) {
    final database = Provider.of<AppDatabase>(context);

    return FutureBuilder<Note?>(
      future: database.getNoteById(widget.noteId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
          );
        }
        final note = snapshot.data;
        if (note == null) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            appBar: AppBar(backgroundColor: const Color(0xFF1E293B)),
            body: const Center(
              child: Text('Note not found', style: TextStyle(color: Colors.white)),
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: note.isPinned ? const Color(0xFF6366F1) : Colors.blueGrey,
                ),
                onPressed: () {
                  database.updateNoteEntry(note.copyWith(isPinned: !note.isPinned));
                  setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _confirmDelete(context, database, note),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        note.summaryTitle ?? 'Untitled Memo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Meta Header
                      Row(
                        children: [
                          Icon(Icons.access_time, color: Colors.blueGrey.withOpacity(0.8), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _formatFullDate(note.createdAt),
                            style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
                          ),
                          if (note.aiProvider != null) ...[
                            const SizedBox(width: 16),
                            Icon(Icons.auto_awesome, color: Colors.indigoAccent.withOpacity(0.8), size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'Summarized via ${note.aiProvider!.toUpperCase()}',
                              style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Color(0xFF334155)),
                      if (note.processingStatus == 'pending_foreground' || note.processingStatus == 'failed') ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: note.processingStatus == 'pending_foreground' 
                                ? Colors.amber.withOpacity(0.1) 
                                : Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: note.processingStatus == 'pending_foreground' 
                                  ? Colors.amber.withOpacity(0.3) 
                                  : Colors.redAccent.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    note.processingStatus == 'pending_foreground'
                                        ? Icons.hourglass_empty
                                        : Icons.error_outline,
                                    color: note.processingStatus == 'pending_foreground'
                                        ? Colors.amber
                                        : Colors.redAccent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    note.processingStatus == 'pending_foreground'
                                        ? 'Queued for AI Summarization'
                                        : 'Summarization Failed',
                                    style: TextStyle(
                                      color: note.processingStatus == 'pending_foreground'
                                          ? Colors.amber
                                          : Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                note.bodyPlainText ?? 'Summarization is pending foreground or has failed.',
                                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: note.processingStatus == 'pending_foreground'
                                        ? Colors.amber.withOpacity(0.2)
                                        : Colors.redAccent.withOpacity(0.2),
                                    foregroundColor: note.processingStatus == 'pending_foreground'
                                        ? Colors.amber
                                        : Colors.redAccent,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: note.processingStatus == 'pending_foreground'
                                            ? Colors.amber.withOpacity(0.5)
                                            : Colors.redAccent.withOpacity(0.5),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  icon: _isRetrying
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.refresh, size: 16),
                                  label: Text(
                                    _isRetrying ? 'Summarizing...' : 'Retry AI Summarization Now',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _isRetrying ? null : () => _handleRetry(context, note.id),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Markdown Body
                      MarkdownBody(
                        data: note.summaryBody ?? 'No summary generated yet.',
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                          h1: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          h2: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          listBullet: const TextStyle(color: Color(0xFF818CF8), fontSize: 18),
                          code: const TextStyle(
                            backgroundColor: Color(0xFF1E293B),
                            color: Color(0xFFE2E8F0),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              // Collapsible Raw Transcript Drawer
              _buildRawTranscriptDrawer(note.rawText),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRawTranscriptDrawer(String rawText) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Row(
              children: [
                Icon(
                  Icons.receipt_long,
                  color: _isRawTranscriptExpanded ? const Color(0xFF6366F1) : Colors.blueGrey,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Original Audio Transcript',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            trailing: Icon(
              _isRawTranscriptExpanded ? Icons.expand_more : Icons.expand_less,
              color: Colors.blueGrey,
            ),
            onTap: () {
              setState(() {
                _isRawTranscriptExpanded = !_isRawTranscriptExpanded;
              });
            },
          ),
          if (_isRawTranscriptExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 24, top: 8),
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  rawText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatFullDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _confirmDelete(BuildContext context, AppDatabase database, Note note) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Delete Note?', style: TextStyle(color: Colors.white)),
          content: const Text(
            'This action will permanently delete this note and its AI summaries.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                await database.deleteNoteById(note.id);
                if (mounted) {
                  Navigator.pop(context); // close dialog
                  context.pop(); // return to list
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleRetry(BuildContext context, int noteId) async {
    if (_isRetrying) return;
    setState(() {
      _isRetrying = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Retrying AI Summarization...'),
        backgroundColor: Color(0xFF6366F1),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final pebbleService = Provider.of<PebbleService>(context, listen: false);
      await pebbleService.retrySummarization(noteId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Summarization completed successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        setState(() {}); // refresh UI
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Retry failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }
}
