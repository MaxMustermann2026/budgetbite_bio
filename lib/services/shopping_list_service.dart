import 'dart:math';

class ShoppingListResult {
  final List<ShoppingLine> lines;

  ShoppingListResult(this.lines);
}

class ShoppingLine {
  final String ingredientId;
  final String name;
  final String unit;

  /// Gesamtbedarf für die Woche
  final double neededAmount;

  /// Aus dem Vorrat verwendete Menge
  final double pantryUsed;

  /// Anzahl zu kaufender Packungen
  final int packages;

  final double unitQuantity;

  final bool isBio;
  final bool canUseBio;

  final int priceConvCents;
  final int? priceBioCents;

  ShoppingLine({
    required this.ingredientId,
    required this.name,
    required this.unit,
    required this.neededAmount,
    required this.pantryUsed,
    required this.packages,
    required this.unitQuantity,
    required this.isBio,
    required this.canUseBio,
    required this.priceConvCents,
    required this.priceBioCents,
  });

  // =========================
  // UI TEXTE
  // =========================

  /// ✅ UI-Text: Bedarf + Vorrat
  String neededText() {
    final base = 'Benötigt: ${_fmtQty(neededAmount)} $unit';
    if (pantryUsed > 0) {
      return '$base  • Vorrat: -${_fmtQty(pantryUsed)} $unit';
    }
    return base;
  }

  /// Einkaufstext (Packungen)
  String purchaseText() {
    if (packages <= 0) {
      return 'Kein Einkauf nötig';
    }
    if (packages == 1) {
      return '1 Packung kaufen';
    }
    return '$packages Packungen kaufen';
  }

  // =========================
  // PREISE
  // =========================

  int totalPriceCents(bool useBio) {
    if (packages <= 0) return 0;

    final pricePerPack =
        useBio && canUseBio && priceBioCents != null ? priceBioCents! : priceConvCents;

    return packages * pricePerPack;
  }

  String totalEuro(bool useBio) {
    final cents = totalPriceCents(useBio);
    return '€${(cents / 100).toStringAsFixed(2)}';
  }

  String packsEuro(bool useBio) {
    if (packages <= 0) return '';
    final pricePerPack =
        useBio && canUseBio && priceBioCents != null ? priceBioCents! : priceConvCents;
    return '${packages}× €${(pricePerPack / 100).toStringAsFixed(2)}';
  }

  // =========================
  // HELPER
  // =========================

  static String _fmtQty(double v) {
    if (v == v.roundToDouble()) {
      return v.toInt().toString();
    }
    return v.toStringAsFixed(1);
  }
}

class ShoppingListService {
  /// Baut die Einkaufsliste aus dem Wochenplan
  Future<ShoppingListResult> buildFromWeekPlan({
    required List<Map<String, dynamic>> weekPlan,
    required int people,
    required bool usePantry,
  }) async {
    final Map<String, _Accumulator> acc = {};

    for (final day in weekPlan) {
      final recipes = (day['recipes'] as List?) ?? [];
      for (final r in recipes) {
        final ingredients = (r['ingredients'] as List?) ?? [];
        for (final ing in ingredients) {
          final id = ing['ingredient_id'] as String;
          final name = ing['name'] as String;
          final unit = ing['unit'] as String;
          final amount = (ing['amount'] as num).toDouble() * people;

          acc.putIfAbsent(
            id,
            () => _Accumulator(
              ingredientId: id,
              name: name,
              unit: unit,
            ),
          );

          acc[id]!.needed += amount;
        }
      }
    }

    final lines = <ShoppingLine>[];

    for (final a in acc.values) {
      final pantryAvailable = usePantry ? a.pantry : 0.0;
      final pantryUsed = min(a.needed, pantryAvailable);
      final remaining = max(0, a.needed - pantryUsed);

      final packages =
          a.unitQuantity > 0 ? (remaining / a.unitQuantity).ceil() : 0;

      lines.add(
        ShoppingLine(
          ingredientId: a.ingredientId,
          name: a.name,
          unit: a.unit,
          neededAmount: a.needed,
          pantryUsed: pantryUsed,
          packages: packages,
          unitQuantity: a.unitQuantity,
          isBio: a.defaultBio,
          canUseBio: a.canUseBio,
          priceConvCents: a.priceConvCents,
          priceBioCents: a.priceBioCents,
        ),
      );
    }

    return ShoppingListResult(lines);
  }

  /// Überträgt gekaufte / verbrauchte Mengen in den Vorrat
  Future<void> applyToPantry({
    required ShoppingListResult result,
    required bool Function(ShoppingLine line) includeLine,
    required bool consumePantryUsed,
    required bool addLeftovers,
  }) async {
    // MVP: Platzhalter – Logik bleibt wie bisher
  }
}

// =========================
// INTERN
// =========================

class _Accumulator {
  final String ingredientId;
  final String name;
  final String unit;

  double needed = 0.0;
  double pantry = 0.0;

  double unitQuantity = 1.0;

  bool defaultBio = false;
  bool canUseBio = true;

  int priceConvCents = 0;
  int? priceBioCents;

  _Accumulator({
    required this.ingredientId,
    required this.name,
    required this.unit,
  });
}