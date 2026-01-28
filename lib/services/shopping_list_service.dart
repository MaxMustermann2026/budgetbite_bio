import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShoppingListResult {
  final List<ShoppingLine> lines;

  ShoppingListResult({required this.lines});

  /// Gesamtwerte berechnen – optional mit UI-Auswahl (ingredientId -> isBio)
  ShoppingTotals totals({Map<String, bool>? selectedBioByIngredientId}) {
    final sel = selectedBioByIngredientId ?? const <String, bool>{};

    int total = 0;
    int bio = 0;

    for (final l in lines) {
      final isBio = sel[l.ingredientId] ?? l.isBio;
      final lineTotal = l.totalPriceCents(isBio);
      total += lineTotal;
      if (isBio) bio += lineTotal;
    }

    final share = total <= 0 ? 0.0 : (bio / total);

    return ShoppingTotals(
      totalCents: total,
      bioCents: bio,
      bioShare: share,
    );
  }

  /// Sortierung – optional mit UI-Auswahl (ingredientId -> isBio)
  List<ShoppingLine> sorted({
    required ShoppingSortMode mode,
    Map<String, bool>? selectedBioByIngredientId,
  }) {
    final sel = selectedBioByIngredientId ?? const <String, bool>{};
    final copy = [...lines];

    switch (mode) {
      case ShoppingSortMode.expensiveFirst:
        copy.sort((a, b) {
          final aBio = sel[a.ingredientId] ?? a.isBio;
          final bBio = sel[b.ingredientId] ?? b.isBio;
          final at = a.totalPriceCents(aBio);
          final bt = b.totalPriceCents(bBio);
          // desc
          final byTotal = bt.compareTo(at);
          if (byTotal != 0) return byTotal;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;

      case ShoppingSortMode.alpha:
        copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }

    return copy;
  }
}

enum ShoppingSortMode { expensiveFirst, alpha }

class ShoppingTotals {
  final int totalCents;
  final int bioCents;

  /// 0..1 (z.B. 0.81)
  final double bioShare;

  ShoppingTotals({
    required this.totalCents,
    required this.bioCents,
    required this.bioShare,
  });

  int get convCents => max(0, totalCents - bioCents);

  String get totalEuro => _fmtEuro(totalCents);
  String get bioEuro => _fmtEuro(bioCents);
  String get convEuro => _fmtEuro(convCents);

  String get bioPercent => '${(bioShare * 100).round()}%';
}

String _fmtEuro(int cents) {
  final v = cents / 100.0;
  return '€${v.toStringAsFixed(2)}';
}

class ShoppingLine {
  final String ingredientId;
  final String name;

  /// Einheit für Anzeige (g, ml, pcs)
  final String unit;

  /// Referenzpackungsgröße (z.B. 1000 g, 240 g, 200 g)
  final double unitQuantity;

  /// Summe, die gebraucht wird (skaliert nach people)
  final double neededAmount;

  /// Wie viele Packungen kaufen wir?
  final int packages;

  /// Tatsächlich gekaufte Menge (= packages * unitQuantity)
  final double purchasedAmount;

  /// Nutzerwunsch aus Rezept (jsonb use_bio)
  final bool requestedBio;

  /// Startwert: wie wir es einkaufen würden (kann UI später überschreiben)
  final bool isBio;

  /// Bio möglich?
  final bool bioAvailable;

  /// Bio ist grundsätzlich möglich + Preis vorhanden
  final bool canUseBio;

  /// Preis pro Packung in Cent
  final int convPricePerPackCents;
  final int? bioPricePerPackCents;

  ShoppingLine({
    required this.ingredientId,
    required this.name,
    required this.unit,
    required this.unitQuantity,
    required this.neededAmount,
    required this.packages,
    required this.purchasedAmount,
    required this.requestedBio,
    required this.isBio,
    required this.bioAvailable,
    required this.canUseBio,
    required this.convPricePerPackCents,
    required this.bioPricePerPackCents,
  });

  /// Preis pro Packung (abhängig von BIO/KONV)
  int pricePerPackCents(bool isBio) {
    if (isBio && canUseBio && bioPricePerPackCents != null && bioPricePerPackCents! > 0) {
      return bioPricePerPackCents!;
    }
    return convPricePerPackCents;
  }

  /// Gesamtpreis der Zeile in Cent (= packages * packPrice)
  int totalPriceCents(bool isBio) {
    return pricePerPackCents(isBio) * packages;
  }

  /// Für UI: "€5.34"
  String totalEuro(bool isBio) => _fmtEuro(totalPriceCents(isBio));

  /// Für UI: "(6× €0.89)"
  String packsEuro(bool isBio) => '(${packages}× ${_fmtEuro(pricePerPackCents(isBio))})';

  /// Für UI: "Benötigt: 575 g"
  String neededText() => 'Benötigt: ${_fmtQty(neededAmount)} $unit';

  /// Für UI: "Einkauf: 6 × 100 g = 600 g • übrig: 25 g"
  String purchaseText() {
    final purchased = purchasedAmount;
    final leftover = max(0.0, purchased - neededAmount);
    return 'Einkauf: $packages × ${_fmtQty(unitQuantity)} $unit = ${_fmtQty(purchased)} $unit'
        ' • übrig: ${_fmtQty(leftover)} $unit';
  }

  String _fmtQty(double v) {
    if ((v - v.roundToDouble()).abs() < 0.0001) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

class ShoppingListService {
  /// MVP: feste Preisregion (später im Setup auswählbar)
  static const String countryCode = 'DE';

  final SupabaseClient _sb = Supabase.instance.client;

  Future<ShoppingListResult> buildFromWeekPlan({
    required List<Map<String, dynamic>> weekPlan,
    required int people,
  }) async {
    // 1) Zutaten aus allen Rezepten sammeln
    final List<_IngUse> uses = [];

    for (final day in weekPlan) {
      final meals = (day['meals'] as List?)?.whereType<Map>().toList() ?? const [];
      for (final meal in meals) {
        final recipe = meal['recipe'];
        if (recipe is! Map) continue;

        final servings = recipe['servings'];
        final servingsNum = (servings is num) ? servings.toDouble() : 1.0;
        final scale = servingsNum <= 0 ? 1.0 : (people / servingsNum);

        final ingredientsRaw = recipe['ingredients'];
        final ingredients = (ingredientsRaw is List) ? ingredientsRaw : const [];

        for (final it in ingredients) {
          if (it is! Map) continue;
          final id = it['ingredient_id']?.toString();
          if (id == null || id.isEmpty) continue;

          final amountRaw = it['amount'];
          final amount = (amountRaw is num) ? amountRaw.toDouble() : 0.0;

          final requestedBio = it['use_bio'] == true;

          uses.add(
            _IngUse(
              ingredientId: id,
              amount: amount * scale,
              requestedBio: requestedBio,
            ),
          );
        }
      }
    }

    if (uses.isEmpty) {
      return ShoppingListResult(lines: []);
    }

    // 2) Aggregieren pro (ingredient_id + requestedBio)
    final Map<String, _Agg> agg = {};
    for (final u in uses) {
      final key = '${u.ingredientId}|${u.requestedBio}';
      agg.putIfAbsent(key, () => _Agg(ingredientId: u.ingredientId, requestedBio: u.requestedBio));
      agg[key]!.needed += u.amount;
    }

    final ingredientIds = uses.map((e) => e.ingredientId).toSet().toList();

    // 3) Zutaten-Stammdaten laden
    final ingredientsRes = await _sb
        .from('ingredients')
        .select('id,name,unit,unit_quantity,bio_available,price_conv_cents,price_bio_cents')
        .inFilter('id', ingredientIds);

    final ingredientsList = (ingredientsRes as List).cast<Map<String, dynamic>>();
    final ingredientsById = {
      for (final row in ingredientsList) row['id'].toString(): row,
    };

    // 4) Preise laden (ingredient_prices) – robust:
    //    - IGNORE rows where ingredient_id is NULL
    //    - choose best per ingredient_id: store NULL first, then newest created_at
    final pricesRes = await _sb
        .from('ingredient_prices')
        .select('ingredient_id,country,store,price_conv_cents,price_bio_cents,unit_quantity,unit,created_at')
        .eq('country', countryCode)
        .inFilter('ingredient_id', ingredientIds);

    final pricesList = (pricesRes as List).cast<Map<String, dynamic>>()
        .where((r) => (r['ingredient_id']?.toString() ?? '').isNotEmpty)
        .toList();

    final Map<String, Map<String, dynamic>> bestPriceByIngredientId = {};
    for (final id in ingredientIds) {
      final rows = pricesList.where((r) => r['ingredient_id']?.toString() == id).toList();
      if (rows.isEmpty) continue;

      rows.sort((a, b) {
        // 1) store NULL bevorzugen
        final aStoreNull = a['store'] == null;
        final bStoreNull = b['store'] == null;
        if (aStoreNull != bStoreNull) return aStoreNull ? -1 : 1;

        // 2) neuestes created_at (desc)
        final aCreated = a['created_at']?.toString() ?? '';
        final bCreated = b['created_at']?.toString() ?? '';
        return bCreated.compareTo(aCreated);
      });

      bestPriceByIngredientId[id] = rows.first;
    }

    // 5) ShoppingLines bauen
    final lines = <ShoppingLine>[];

    for (final entry in agg.values) {
      final ingId = entry.ingredientId;
      final ingRow = ingredientsById[ingId];

      final name = (ingRow?['name'] ?? 'Zutat').toString();

      final priceRow = bestPriceByIngredientId[ingId];

      // Einheit + Packungsgröße:
      // bevorzugt aus ingredient_prices, fallback ingredient-stammdaten
      final unit = (priceRow?['unit'] ?? ingRow?['unit'] ?? '').toString();
      final unitQtyRaw = priceRow?['unit_quantity'] ?? ingRow?['unit_quantity'] ?? 1;
      final unitQuantity = (unitQtyRaw is num) ? unitQtyRaw.toDouble() : 1.0;

      // Preise: bevorzugt ingredient_prices, fallback ingredients (alt)
      final convRaw = priceRow?['price_conv_cents'] ?? ingRow?['price_conv_cents'] ?? 0;
      final bioRaw = priceRow?['price_bio_cents'] ?? ingRow?['price_bio_cents'];

      final convPrice = (convRaw is num) ? convRaw.toInt() : 0;
      final bioPrice = (bioRaw is num) ? bioRaw.toInt() : null;

      final bioAvailable = ingRow?['bio_available'] == true;
      final canUseBio = bioAvailable && (bioPrice != null && bioPrice > 0);

      // Wenn keine Packungsgröße korrekt gesetzt ist, vermeiden wir /0
      final safeUnitQty = unitQuantity <= 0 ? 1.0 : unitQuantity;

      final needed = entry.needed;
      final packages = max(1, (needed / safeUnitQty).ceil());
      final purchased = packages * safeUnitQty;

      // Startwert: BIO wenn gewünscht und möglich
      final isBio = entry.requestedBio && canUseBio;

      lines.add(
        ShoppingLine(
          ingredientId: ingId,
          name: name,
          unit: unit,
          unitQuantity: safeUnitQty,
          neededAmount: needed,
          packages: packages,
          purchasedAmount: purchased,
          requestedBio: entry.requestedBio,
          isBio: isBio,
          bioAvailable: bioAvailable,
          canUseBio: canUseBio,
          convPricePerPackCents: convPrice,
          bioPricePerPackCents: bioPrice,
        ),
      );
    }

    return ShoppingListResult(lines: lines);
  }
}

class _IngUse {
  final String ingredientId;
  final double amount;
  final bool requestedBio;

  _IngUse({
    required this.ingredientId,
    required this.amount,
    required this.requestedBio,
  });
}

class _Agg {
  final String ingredientId;
  final bool requestedBio;
  double needed = 0;

  _Agg({
    required this.ingredientId,
    required this.requestedBio,
  });
}