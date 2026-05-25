import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'src/data/database.dart';
import 'src/ai/ai_service.dart';
import 'src/pebble/pebble_service.dart';
import 'src/ui/note_list_page.dart';
import 'src/ui/note_detail_page.dart';
import 'src/ui/settings_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase();
  final aiService = AIServiceRouter();
  final pebbleService = PebbleService(
    database: database,
    aiService: aiService,
  );

  // Start listening to watch app messages in background
  pebbleService.start();

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<AIService>.value(value: aiService),
        Provider<PebbleService>.value(value: pebbleService),
      ],
      child: const MyApp(),
    ),
  );
}

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const NoteListPage(),
    ),
    GoRoute(
      path: '/detail/:id',
      builder: (context, state) {
        final idStr = state.pathParameters['id']!;
        final id = int.parse(idStr);
        return NoteDetailPage(noteId: id);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MindCorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1), // Indigo accent
          secondary: Color(0xFF818CF8),
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
