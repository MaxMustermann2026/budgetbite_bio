import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'shopping_list_screen.dart';
import 'recipe_detail_screen.dart';

class PlanScreen extends StatefulWidget {
  final double budgetEuro;
  final int people;
  final int bioTargetPercent;
  final bool showRecipes;
  final String diet; // omnivore | vegetarian | vegan
  final int mealsPerDay; // 1..3

  const PlanScreen({
    super.key,
    required this.budgetEuro,
    required this.people,
    required this.bioTargetPercent,
    required this.showRecipes,
    required this.diet,
    required this.mealsPerDay,
  });

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool loading = true;
  String? error;

  final List<String> weekdays = const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  final List<String> mealLabels = const ['Frühstück', 'Mittag', 'Abend'];

  List<Map<String, dynamic>> weekPlan = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final supabase = Supabase.instance.client;

      // Base query
      final base = supabase.from('recipes').select('*');

      // Diet filter
      dynamic query;
      if (widget.diet == 'vegan') {
        query = base.eq('diet', 'vegan');
      } else if (widget.diet == 'vegetarian') {
        // vegetarian includes vegan
        query = base.or('diet.eq.vegetarian,diet.eq.vegan');
      } else {
        // omnivore -> all (for MVP)
        query = base;
      }

      // Your table uses "title"
      final res = await query.order('title', ascending: true);
      final list = (res as List).cast<Map<String, dynamic>>();

      // Split by meal_type
      final breakfastRecipes =
          list.where((r) => (r['meal_type'] ?? '').toString() == 'breakfast').toList();
      final lunchRecipes =
          list.where((r) => (r['meal_type'] ?? '').toString() == 'lunch').toList();
      final dinnerRecipes =
          list.where((r) => (r['meal_type'] ?? '').toString() == 'dinner').toList();

      // Lunch preferred = quick/no_cook
      final lunchPreferredRecipes = lunchRecipes.where((r) {
        final lvl = (r['prep_level'] ?? '').toString();
        return lvl == 'no_cook' || lvl == 'quick';
      }).toList();

      // Lunch mixed: preferred first, then remaining lunch recipes (e.g., cook)
      final lunchMixedRecipes = <Map<String, dynamic>>[
        ...lunchPreferredRecipes,
        ...lunchRecipes.where(
          (r) => !lunchPreferredRecipes.any((p) => p['id'] == r['id']),
        ),
      ];

      // Separate indices per slot (stable rotation)
      int breakfastIndex = 0;
      int lunchIndex = 0;
      int dinnerIndex = 0;

      List<Map<String, dynamic>> poolForLabel(String label) {
        if (label == 'Frühstück') return breakfastRecipes;
        if (label == 'Mittag') return lunchMixedRecipes;
        return dinnerRecipes; // Abend
      }

      // Generate plan
      final generatedPlan = <Map<String, dynamic>>[];

      for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
        final meals = <Map<String, dynamic>>[];

        for (int m = 0; m < widget.mealsPerDay; m++) {
          final label = mealLabels[m];
          final pool = poolForLabel(label);

          Map<String, dynamic>? recipe;
          if (pool.isEmpty) {
            recipe = null;
          } else if (label == 'Frühstück') {
            recipe = pool[breakfastIndex % pool.length];
            breakfastIndex++;
          } else if (label == 'Mittag') {
            recipe = pool[lunchIndex % pool.length];
            lunchIndex++;
          } else {
            recipe = pool[dinnerIndex % pool.length];
            dinnerIndex++;
          }

          meals.add({'label': label, 'recipe': recipe});
        }

        generatedPlan.add({'day': weekdays[dayIndex], 'meals': meals});
      }

      setState(() {
        weekPlan = generatedPlan;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  void _openRecipeIfEnabled(Map<String, dynamic>? recipe) {
    if (!widget.showRecipes) return;
    if (recipe == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(recipe: recipe),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = 'Budget: €${widget.budgetEuro.toStringAsFixed(0)} • '
        'Personen: ${widget.people} • '
        'Bio-Ziel: ${widget.bioTargetPercent}% • '
        'Rezepte: ${widget.showRecipes ? "ja" : "nein"} • '
        'Ernährung: ${widget.diet} • '
        'Mahlzeiten/Tag: ${widget.mealsPerDay}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dein Wochenplan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: (loading || error != null || weekPlan.isEmpty)
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ShoppingListScreen(
                          budgetEuro: widget.budgetEuro,
                          people: widget.people,
                          bioTargetPercent: widget.bioTargetPercent,
                          weekPlan: weekPlan,
                        ),
                      ),
                    );
                  },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : (error != null)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fehler:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(error!),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Erneut versuchen')),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(header),
                      const SizedBox(height: 16),
                      const Text(
                        '7-Tage-Plan (MVP):',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: weekPlan.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final day = weekPlan[i]['day'] as String;
                            final meals =
                                (weekPlan[i]['meals'] as List).cast<Map<String, dynamic>>();

                            return ExpansionTile(
                              title: Text(day, style: const TextStyle(fontWeight: FontWeight.bold)),
                              children: meals.map((m) {
                                final label = m['label'] as String;
                                final recipe = m['recipe'] as Map<String, dynamic>?;

                                final title = recipe == null
                                    ? '—'
                                    : (recipe['title'] ?? 'Unbenannt').toString();

                                final tappable = widget.showRecipes && recipe != null;

                                return ListTile(
                                  title: Text('$label: $title'),
                                  subtitle: tappable
                                      ? const Text('Tippen für Details', style: TextStyle(fontSize: 12))
                                      : null,
                                  trailing: tappable ? const Icon(Icons.chevron_right) : null,
                                  onTap: tappable ? () => _openRecipeIfEnabled(recipe) : null,
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}