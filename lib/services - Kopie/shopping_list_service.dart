import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ===========================
/// PANTRY (SharedPreferences)
/// ===========================

class PantryEntry {
  final String unit; // g | ml | pcs
  final double amount;

  const PantryEntry({required this.unit, required this.amount});

  Map<String, dynamic> toJson() => {'unit': unit, 'amount': amount};

  static PantryEntry fromJson(Map<String, dynamic> json) {
    return PantryEntry(
      unit: json['unit'] as String,
      amount: (json['amount'] as num).toDouble(),
    );
  }
}

class PantryStore {
  static const _key = 'budgetbite_pantry_v1';

  static Future<Map<String, PantryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (k, v) => MapEntry(k, PantryEntry.fromJson(Map<String, dynamic>.from(v))),
    );
  }

  static Future<void> save(Map<String, PantryEntry> pantry) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = pantry.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_key, jsonEncode(encoded));
  }

  static double getAmount(
    Map<String, PantryEntry> pantry,
    String ingredientId,
    String unit,
  ) {
    final entry = pantry[ingredientId];
    if (entry == null || entry.unit != unit) return 0;
    return entry.amount;
  }

  static void consume(
    Map<String, PantryEntry> pantry,
    String ingredientId,
    String unit,
    double amount,
  ) {
    final entry = pantry[ingredientId];
    if (entry == null || entry.unit != unit) return;

    final left = math.max(0, entry.amount - amount);
    if (left == 0) {
      pantry.remove(ingredientId);
    } else {
      pantry[ingredientId] = PantryEntry(unit: unit, amount: left);
    }
  }

  static void add(
    Map<String, PantryEntry> pantry,
    String ingredientId,
    String unit,
    double amount,
  ) {
    if (amount <= 0) return;
    final entry = pantry[ingredientId];
    pantry[ingredientId] = PantryEntry(
      unit: unit,
      amount: (entry?.amount ?? 0) + amount,
    );
  }
}

/// ===========================
/// MODELS
/// ===========================

class ShoppingListLine {
  final String ingredientId;
  final String name;
  final String unit;
  final bool requestedBio;

  final double requiredAmountOriginal;
  final double pantryUsed;
  final double requiredAmount;

  final double packageSize;
  final int packages;
  final double purchasedAmount;

  final int pricePerPackageCents;
  final int totalCostCents;

  const ShoppingListLine({
    required this.ingredientId,
    required this.name,
    required this.unit,
    required this.requestedBio,
    required this.requiredAmountOriginal,
    required this.pantryUsed,
    required this.requiredAmount,
    required this.packageSize,
    required this.packages,
    required this.purchasedAmount,
    required this.pricePerPackageCents,
    required this.totalCostCents,
  });
}

/// 🔁 Alias für bestehende Screens
typedef ShoppingLine = ShoppingListLine;

class ShoppingListResult {
  final List<ShoppingListLine> lines;
  final int totalCostCents;
  final int totalBioCostCents;
  final int totalConvCostCents;

  const ShoppingListResult({
    required this.lines,
    required this.totalCostCents,
    required this.totalBioCostCents,
    required this.totalConvCostCents,
  });
}

/// ===========================
/// SERVICE
/// ===========================

class ShoppingListService {
  final SupabaseClient _client;

  ShoppingListService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// 🔹 Static Wrapper (für bestehende Screens)
  static Future<ShoppingListResult> buildFromWeekPlan(
    dynamic weekPlan,
    int people, {
    String country = 'DE',
    bool usePantry = true,
  }) {
    return ShoppingListService()._build(
      weekPlan,
      people,
      country: country,
      usePantry: usePantry,
    );
  }

  static Future<void> applyResultToPantry(
    ShoppingListResult result, {
    required bool Function(ShoppingListLine line) takeIntoPantryFilter,
  }) {
    return ShoppingListService()._apply(result,
        takeIntoPantryFilter: takeIntoPantryFilter);
  }

  /// ---------------- internal ----------------

  Future<ShoppingListResult> _build(
    dynamic weekPlan,
    int people, {
    required String country,
    required bool usePantry,
  }) async {
    final pantry = usePantry ? await PantryStore.load() : <String, PantryEntry>{};
    final lines = <ShoppingListLine>[];

    int total = 0;
    int bio = 0;
    int conv = 0;

    for (final recipe in _extractRecipes(weekPlan)) {
      final servings = (recipe['servings'] as num?)?.toDouble() ?? 1;
      final factor = people / servings;

      for (final ing in recipe['ingredients']) {
        final ingredientId = ing['ingredient_id'] as String;
        final name = ing['name'] as String? ?? ingredientId;
        final unit = ing['unit'] as String? ?? 'g';
        final amount = (ing['amount'] as num).toDouble() * factor;
        final bioFlag = ing['use_bio'] == true;

        final pantryUsed =
            math.min(amount, PantryStore.getAmount(pantry, ingredientId, unit));
        final needed = amount - pantryUsed;

        final packageSize = 1.0;
        final packages = needed <= 0 ? 0 : needed.ceil();
        final purchased = packages * packageSize;
        final price = 0;
        final cost = packages * price;

        total += cost;
        bioFlag ? bio += cost : conv += cost;

        lines.add(
          ShoppingListLine(
            ingredientId: ingredientId,
            name: name,
            unit: unit,
            requestedBio: bioFlag,
            requiredAmountOriginal: amount,
            pantryUsed: pantryUsed,
            requiredAmount: needed,
            packageSize: packageSize,
            packages: packages,
            purchasedAmount: purchased,
            pricePerPackageCents: price,
            totalCostCents: cost,
          ),
        );
      }
    }

    return ShoppingListResult(
      lines: lines,
      totalCostCents: total,
      totalBioCostCents: bio,
      totalConvCostCents: conv,
    );
  }

  Future<void> _apply(
    ShoppingListResult result, {
    required bool Function(ShoppingListLine line) takeIntoPantryFilter,
  }) async {
    final pantry = await PantryStore.load();

    for (final line in result.lines) {
      if (line.pantryUsed > 0) {
        PantryStore.consume(
            pantry, line.ingredientId, line.unit, line.pantryUsed);
      }
      if (takeIntoPantryFilter(line)) {
        PantryStore.add(
            pantry, line.ingredientId, line.unit, line.purchasedAmount);
      }
    }

    await PantryStore.save(pantry);
  }

  List<Map<String, dynamic>> _extractRecipes(dynamic weekPlan) {
    final out = <Map<String, dynamic>>[];

    void walk(dynamic n) {
      if (n is Map && n.containsKey('ingredients')) out.add(n.cast());
      if (n is Map) n.values.forEach(walk);
      if (n is List) n.forEach(walk);
    }

    walk(weekPlan);
    return out;
  }
}