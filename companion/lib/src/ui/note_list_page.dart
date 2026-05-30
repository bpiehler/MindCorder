import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../data/database.dart';
import '../pebble/pebble_service.dart';
import 'package:drift/drift.dart' as drift;
import 'voice_capture_sheet.dart';
import 'timeline_helper.dart';
import 'search_helper.dart';
import 'dart:ui';

class NoteListPage extends StatefulWidget {
  const NoteListPage({super.key});

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  bool _isWatchConnected = false;
  late final Stream<List<Note>> _notesStream;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

          // Calculate similarity scores if search query is active
          List<MapEntry<Note, double>> scoredNotes = [];
          if (_searchQuery.isNotEmpty) {
            for (final note in notes) {
              final similarity = SemanticSearchEngine.computeSimilarity(
                query: _searchQuery,
                title: note.summaryTitle ?? '',
                body: note.summaryBody ?? '',
                rawText: note.rawText,
              );
              if (similarity > 0.0) {
                scoredNotes.add(MapEntry(note, similarity));
              }
            }
            // Sort by semantic similarity descending
            scoredNotes.sort((a, b) => b.value.compareTo(a.value));
          } else {
            scoredNotes = notes.map((n) => MapEntry(n, 1.0)).toList();
          }

          final similarityMap = Map.fromEntries(scoredNotes.map((e) => MapEntry(e.key.id, e.value)));

          // Check if searching returned absolutely no matches
          if (scoredNotes.isEmpty && _searchQuery.isNotEmpty) {
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildSearchBar(),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_outlined,
                          size: 64,
                          color: Colors.blueGrey.withOpacity(0.4),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No matching thoughts found',
                          style: TextStyle(color: Colors.blueGrey, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try searching for synonyms or related concepts!',
                          style: TextStyle(
                            color: Colors.blueGrey.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          final List<TimelineGroup> groups;
          if (_searchQuery.isNotEmpty) {
            groups = [
              TimelineGroup(
                title: 'SEMANTIC MATCHES',
                notes: scoredNotes.map((e) => e.key).toList(),
              )
            ];
          } else {
            groups = TimelineCategorizer.groupNotes(notes);
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _buildSearchBar(),
              ),
              for (final group in groups) ...[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: GlassmorphicHeaderDelegate(title: group.title),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(left: 12, right: 16, top: 8, bottom: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final note = group.notes[index];
                        final isFirst = index == 0;
                        final isLast = index == group.notes.length - 1;
                        final similarity = similarityMap[note.id];
                        return _buildTimelineRow(
                          context,
                          note,
                          database,
                          isFirst,
                          isLast,
                          similarity: similarity,
                        );
                      },
                      childCount: group.notes.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
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

  Widget _buildNoteCard(
    BuildContext context,
    Note note,
    AppDatabase database, {
    double? similarity,
  }) {
    final title = note.summaryTitle ?? 'Processing note...';
    final hasFailed = note.processingStatus == 'failed';
    final isProcessing = note.processingStatus == 'processing';

    return Dismissible(
      key: Key(note.id.toString()),
      background: Container(
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
        margin: EdgeInsets.zero,
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
              if (_searchQuery.isNotEmpty && similarity != null && similarity > 0.0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3), width: 1),
                  ),
                  child: Text(
                    '${(similarity * 100).toStringAsFixed(0)}% MATCH',
                    style: const TextStyle(
                      color: Color(0xFF818CF8),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
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

  Widget _buildTimelineRow(
    BuildContext context,
    Note note,
    AppDatabase database,
    bool isFirst,
    bool isLast, {
    double? similarity,
  }) {
    final isWatch = note.watchId != null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vertical thread segment
          SizedBox(
            width: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: isFirst ? 24 : 0,
                  bottom: isLast ? 24 : 0,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          isWatch ? const Color(0xFF6366F1) : const Color(0xFF14B8A6),
                          isWatch ? const Color(0xFF818CF8) : const Color(0xFF2DD4BF),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isWatch
                          ? const Color(0xFF6366F1).withOpacity(0.15)
                          : const Color(0xFF14B8A6).withOpacity(0.15),
                      border: Border.all(
                        color: isWatch ? const Color(0xFF6366F1) : const Color(0xFF14B8A6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isWatch
                              ? const Color(0xFF6366F1).withOpacity(0.3)
                              : const Color(0xFF14B8A6).withOpacity(0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      isWatch ? Icons.watch : Icons.phone_android,
                      color: isWatch ? const Color(0xFF818CF8) : const Color(0xFF2DD4BF),
                      size: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _buildNoteCard(
                context,
                note,
                database,
                similarity: similarity,
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search thoughts semantically...',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFF818CF8),
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.blueGrey, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassmorphicHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;

  GlassmorphicHeaderDelegate({required this.title});

  @override
  double get minExtent => 38.0;

  @override
  double get maxExtent => 38.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 38.0,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xDD0F172A),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.06),
                width: 1,
              ),
              top: BorderSide(
                color: Colors.white.withOpacity(0.04),
                width: 1,
              ),
            ),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF818CF8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant GlassmorphicHeaderDelegate oldDelegate) {
    return oldDelegate.title != title;
  }
}
