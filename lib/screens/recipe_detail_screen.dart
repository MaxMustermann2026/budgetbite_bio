import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late final Future<Map<String, Map<String, dynamic>>> _ingredientLookupFuture;

  @override
  void initState() {
    super.initState();
    _ingredientLookupFuture = _loadIngredientLookup();
  }

  Future<Map<String, Map<String, dynamic>>> _loadIngredientLookup() async {
    final ingredientsRaw = widget.recipe['ingredients'];
    final items = (ingredientsRaw is List) ? ingredientsRaw : const [];

    // IDs aus jsonb sammeln
    final ids = <String>{};
    for (final it in items) {
      if (it is Map && it['ingredient_id'] != null) {
        ids.add(it['ingredient_id'].toString());
      }
    }
    if (ids.isEmpty) return {};

    final supabase = Supabase.instance.client;

    // Zutaten-Stammdaten laden
    // Falls dein supabase_flutter KEIN "inFilter" hat, ersetze es durch: .in_('id', ids.toList())
    final res = await supabase
        .from('ingredients')
        .select('id,name,unit,unit_quantity')
        .inFilter('id', ids.toList());

    final list = (res as List).cast<Map<String, dynamic>>();

    return {
      for (final row in list) row['id'].toString(): row,
    };
  }

  String _fmtAmount(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      final d = v.toDouble();
      if (d >= 10) return d.toStringAsFixed(0);
      return d.toStringAsFixed(1);
    }
    return v.toString();
  }

  String _mealTypeLabel(String? v) {
    switch (v) {
      case 'breakfast':
        return 'Frühstück';
      case 'lunch':
        return 'Mittag';
      case 'dinner':
        return 'Abend';
      default:
        return v ?? '';
    }
  }

  String _prepLabel(String? v) {
    switch (v) {
      case 'no_cook':
        return 'no-cook';
      case 'quick':
        return 'quick';
      case 'cook':
        return 'cook';
      default:
        return v ?? '';
    }
  }

  List<String> _instructionSteps(String? instructions) {
    if (instructions == null) return [];
    final t = instructions.trim();
    if (t.isEmpty) return [];
    return t
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;

    // ✅ passt zu deiner Supabase recipes-Tabelle
    final title = (recipe['title'] ?? 'Rezept').toString();
    final diet = recipe['diet']?.toString();
    final mealType = recipe['meal_type']?.toString();
    final prepLevel = recipe['prep_level']?.toString();
    final servings = recipe['servings'];

    final instructions = recipe['instructions']?.toString();
    final steps = _instructionSteps(instructions);

    // jsonb ingredients: List<Map>
    final ingredientsRaw = recipe['ingredients'];
    final ingredients = (ingredientsRaw is List)
        ? ingredientsRaw
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<Map<String, Map<String, dynamic>>>(
        future: _ingredientLookupFuture,
        builder: (context, snap) {
          final lookup = snap.data ?? const <String, Map<String, dynamic>>{};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (servings != null) Chip(label: Text('$servings Portionen')),
                  if (diet != null && diet.isNotEmpty) Chip(label: Text(diet)),
                  if (mealType != null && mealType.isNotEmpty) Chip(label: Text(_mealTypeLabel(mealType))),
                  if (prepLevel != null && prepLevel.isNotEmpty) Chip(label: Text(_prepLabel(prepLevel))),
                  if (snap.connectionState != ConnectionState.done)
                    const Chip(label: Text('Zutaten laden…')),
                ],
              ),
              const SizedBox(height: 12),

              if (steps.isNotEmpty) ...[
                const Text('Anleitung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...List.generate(
                  steps.length,
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Expanded(child: Text(steps[i])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (instructions != null && instructions.trim().isNotEmpty) ...[
                const Text('Anleitung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(instructions),
                const SizedBox(height: 16),
              ],

              const Text('Zutaten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),

              if (ingredients.isEmpty) const Text('Keine Zutaten hinterlegt.'),

              ...ingredients.map((ing) {
                final id = ing['ingredient_id']?.toString();
                final amount = ing['amount'];
                final useBio = ing['use_bio'] == true;

                final row = (id != null) ? lookup[id] : null;

                // Debug-Hinweis, falls IDs nicht matchen
                if (id != null && row == null) {
                  // ignore: avoid_print
                  print('Ingredient nicht gefunden: $id');
                }

                // Fallbacks (falls alte Struktur drin ist)
                final fallbackName =
                    (ing['name'] ?? ing['label'] ?? ing['ingredient_name'] ?? 'Zutat').toString();

                final name = (row?['name'] ?? fallbackName).toString();
                final unit = (row?['unit'] ?? ing['unit'] ?? '').toString();

                final right = amount == null
                    ? ''
                    : (unit.isEmpty ? _fmtAmount(amount) : '${_fmtAmount(amount)} $unit');

                // ✅ DEIN gewünschtes UI (leicht angepasst: zeigt Menge unter Name)
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (right.isNotEmpty)
                              Text(
                                right,
                                style: const TextStyle(color: Colors.black54),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: useBio
                              ? Colors.green.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          useBio ? 'BIO' : 'KONV',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: useBio ? Colors.green : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}