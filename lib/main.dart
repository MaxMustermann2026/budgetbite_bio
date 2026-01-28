import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/setup_screen.dart';

const supabaseUrl = 'https://oaxkzbgtaxbksnljqlrg.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9heGt6Ymd0YXhia3NubGpxbHJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NTUzNzAsImV4cCI6MjA4NDMzMTM3MH0.neqAkt3d1WaLKcYksgeQkoX01b1mlBlv2eAZ44YCE5U';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BudgetBite Bio',
      theme: ThemeData(useMaterial3: true),
      home: SetupScreen(),
    );
  }
}

class HealthcheckScreen extends StatefulWidget {
  const HealthcheckScreen({super.key});

  @override
  State<HealthcheckScreen> createState() => _HealthcheckScreenState();
}

class _HealthcheckScreenState extends State<HealthcheckScreen> {
  bool? connected;
  String? error;
  int? ingredientsCount;
  int? recipesCount;
  int? weeklyPlanCount;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() {
      connected = null;
      error = null;
      ingredientsCount = null;
      recipesCount = null;
      weeklyPlanCount = null;
    });

    try {
      final supabase = Supabase.instance.client;

      final ing = await supabase.from('ingredients').select('id');
      final rec = await supabase.from('recipes').select('id');
      final wp = await supabase.from('weekly_plan').select('*');

      setState(() {
        connected = true;
        ingredientsCount = (ing as List).length;
        recipesCount = (rec as List).length;
        weeklyPlanCount = (wp as List).length;
      });
    } catch (e) {
      setState(() {
        connected = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = connected == null
        ? 'Prüfe Verbindung...'
        : (connected == true ? '✅ Verbunden' : '❌ Nicht verbunden');

    return Scaffold(
      appBar: AppBar(title: const Text('Healthcheck')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(statusText, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            if (connected == true) ...[
              Text('ingredients: ${ingredientsCount ?? 0}'),
              Text('recipes: ${recipesCount ?? 0}'),
              Text('weekly_plan: ${weeklyPlanCount ?? 0}'),
            ],
            if (connected == false) ...[
              const SizedBox(height: 12),
              const Text('Fehler:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(error ?? ''),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _runChecks,
                child: const Text('Erneut prüfen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
