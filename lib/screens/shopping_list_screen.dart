import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/shopping_list_service.dart';

enum SortMode {
  expensiveFirst,
  alphabetic,
  bioFirst,
}

class ShoppingListScreen extends StatefulWidget {
  final double budgetEuro;
  final int people;
  final int bioTargetPercent;
  final List<Map<String, dynamic>> weekPlan;

  const ShoppingListScreen({
    super.key,
    required this.budgetEuro,
    required this.people,
    required this.bioTargetPercent,
    required this.weekPlan,
  });

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  // UI state
  SortMode sortMode = SortMode.expensiveFirst;
  bool shoppingMode = false;

  /// Abhaken (nur UI)
  final Set<String> checked = {}; // key = "$ingredientId|$requestedBio"

  /// BIO/KONV Override pro Zeile (nur UI)
  /// value=true => BIO, value=false => KONV
  final Map<String, bool> purchaseBioOverride = {}; // key = "$ingredientId|$requestedBio"

  /// Persistenz-Key (einfach MVP: eine Einkaufsliste)
  static const _prefsKey = 'shopping_list_state_v2';

  late final Future<void> _prefsInitFuture;

  @override
  void initState() {
    super.initState();
    _prefsInitFuture = _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;

    try {
      final obj = jsonDecode(raw) as Map<String, dynamic>;

      final sortIndex = (obj['sortMode'] as num?)?.toInt() ?? 0;
      final sm = SortMode.values[sortIndex.clamp(0, SortMode.values.length - 1)];

      final mode = obj['shoppingMode'] == true;

      final checkedList =
          (obj['checked'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];

      final overrideMap = (obj['override'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v == true),
          ) ??
          <String, bool>{};

      if (!mounted) return;

      setState(() {
        sortMode = sm;
        shoppingMode = mode;

        checked
          ..clear()
          ..addAll(checkedList);

        purchaseBioOverride
          ..clear()
          ..addAll(overrideMap);
      });
    } catch (_) {
      // MVP: ignorieren
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final obj = <String, dynamic>{
      'sortMode': sortMode.index,
      'shoppingMode': shoppingMode,
      'checked': checked.toList(),
      'override': purchaseBioOverride,
    };

    await prefs.setString(_prefsKey, jsonEncode(obj));
  }

  Future<void> _clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  // --- Helpers ---

  String _lineKey(ShoppingLine line) => '${line.ingredientId}|${line.requestedBio}';

  bool _selectedBio(ShoppingLine line) {
    final key = _lineKey(line);
    return purchaseBioOverride[key] ?? line.isBio;
  }

  (int totalCostCents, int bioCostCents) _computeTotals(List<ShoppingLine> lines) {
    int total = 0;
    int bio = 0;

    for (final l in lines) {
      final key = _lineKey(l);
      final isBio = purchaseBioOverride[key] ?? l.isBio;

      final cost = l.totalPriceCents(isBio);
      total += cost;

      if (isBio && l.canUseBio) {
        bio += cost;
      }
    }

    return (total, bio);
  }

  List<ShoppingLine> _sortedLines(List<ShoppingLine> lines) {
    final unchecked = <ShoppingLine>[];
    final done = <ShoppingLine>[];

    for (final l in lines) {
      // ✅ A2c: Pantry-only Items im Einkaufsmodus ausblenden
      // (packages == 0 bedeutet: vollständig durch Pantry gedeckt)
      if (shoppingMode && l.packages == 0) {
        continue;
      }

      if (shoppingMode && checked.contains(_lineKey(l))) {
        done.add(l);
      } else {
        unchecked.add(l);
      }
    }

    int byMode(ShoppingLine a, ShoppingLine b) {
      int totalCents(ShoppingLine x) {
        final isBio = _selectedBio(x);
        return x.totalPriceCents(isBio);
      }

      switch (sortMode) {
        case SortMode.alphabetic:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());

        case SortMode.bioFirst:
          final ab = _selectedBio(a) && a.canUseBio;
          final bb = _selectedBio(b) && b.canUseBio;
          if (ab != bb) return ab ? -1 : 1;
          return totalCents(b).compareTo(totalCents(a));

        case SortMode.expensiveFirst:
        default:
          return totalCents(b).compareTo(totalCents(a));
      }
    }

    unchecked.sort(byMode);
    done.sort(byMode);

    return shoppingMode ? [...unchecked, ...done] : unchecked;
  }

  String _sortLabel() {
    switch (sortMode) {
      case SortMode.alphabetic:
        return 'Alphabetisch (A–Z)';
      case SortMode.bioFirst:
        return 'BIO zuerst';
      case SortMode.expensiveFirst:
      default:
        return 'Teuerste zuerst';
    }
  }

  Future<void> _copyToClipboard({
    required int totalCostCents,
    required int bioCostCents,
    required List<ShoppingLine> lines,
  }) async {
    final bioSharePercent =
        totalCostCents == 0 ? 0 : ((bioCostCents / totalCostCents) * 100).round();
    final plannedEuro = totalCostCents / 100.0;

    final buffer = StringBuffer();
    buffer.writeln('BudgetBite Bio – Einkaufsliste');
    buffer.writeln('Budget: €${widget.budgetEuro.toStringAsFixed(0)}');
    buffer.writeln('Geplant: €${plannedEuro.toStringAsFixed(2)}');
    buffer.writeln('Bio-Anteil (Ist): $bioSharePercent% • Bio-Ziel: ${widget.bioTargetPercent}%');
    buffer.writeln('Modus: ${shoppingMode ? "EINKAUF" : "PLANUNG"}');
    buffer.writeln('Sortierung: ${_sortLabel()}');
    if (shoppingMode) {
      buffer.writeln('Erledigt: ${checked.length.clamp(0, lines.length)} / ${lines.length}');
    }
    buffer.writeln('');

    for (final line in lines) {
      final key = _lineKey(line);
      final isBio = (purchaseBioOverride[key] ?? line.isBio) && line.canUseBio;
      final badge = isBio ? 'BIO' : 'KONV';

      final doneMark = (shoppingMode && checked.contains(key)) ? '☑ ' : '☐ ';

      final price = line.totalEuro(isBio);

      buffer.writeln('$doneMark${line.name} [$badge] — ${line.purchaseText()} — $price');

      if ((purchaseBioOverride[key] == true) && !line.canUseBio) {
        buffer.writeln('   Hinweis: Bio nicht verfügbar → Konv.');
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Einkaufsliste in Zwischenablage kopiert')),
    );
  }

  void _setBioForLine(ShoppingLine line, bool wantBio) {
    final key = _lineKey(line);

    if (wantBio && !line.canUseBio) {
      setState(() {
        purchaseBioOverride[key] = false;
      });
      _savePrefs();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bio für "${line.name}" nicht verfügbar – bleibt konventionell.')),
      );
      return;
    }

    setState(() {
      purchaseBioOverride[key] = wantBio;
    });
    _savePrefs();
  }

  Future<void> _resetAll() async {
    setState(() {
      checked.clear();
      purchaseBioOverride.clear();
      shoppingMode = false;
      sortMode = SortMode.expensiveFirst;
    });
    await _clearPrefs();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Zurückgesetzt')),
    );
  }

  Widget _modeBanner() {
    final isShop = shoppingMode;

    final icon = isShop ? Icons.shopping_cart : Icons.tune;
    final title = isShop ? 'EINKAUFSMODUS' : 'PLANUNGSMODUS';
    final subtitle = isShop ? 'Häkchen setzen im Laden' : 'BIO/KONV & Budget optimieren';

    final bg = isShop ? Colors.blue.withOpacity(0.08) : Colors.green.withOpacity(0.08);
    final fg = isShop ? Colors.blue.shade700 : Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => shoppingMode = !shoppingMode);
              _savePrefs();
            },
            child: Text(isShop ? 'Zur Planung' : 'Zum Einkauf'),
          ),
        ],
      ),
    );
  }

  Widget _bioKonvToggle(ShoppingLine line) {
    final selectedBio = _selectedBio(line) && line.canUseBio;
    final canBio = line.canUseBio;

    final canEdit = !shoppingMode;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoiceChip(
          label: const Text('KONV'),
          selected: !selectedBio,
          onSelected: !canEdit ? null : (_) => _setBioForLine(line, false),
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          label: const Text('BIO'),
          selected: selectedBio,
          onSelected: !canEdit ? null : (_) => _setBioForLine(line, true),
          disabledColor: Colors.grey.withOpacity(0.15),
        ),
        if (!canBio)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text('Bio n/v', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        if (shoppingMode)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text('Fix', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
      ],
    );
  }

  Future<void> _applyBoughtToPantry(ShoppingListService service, ShoppingListResult result) async {
    if (checked.isEmpty) return;

    await service.applyToPantry(
      result: result,
      includeLine: (line) => checked.contains(_lineKey(line)),
      consumePantryUsed: false, // im Laden: wir buchen erstmal nur "Reste aus gekauften"
      addLeftovers: true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gekauftes in Pantry übernommen (Reste)')),
    );
  }

  Future<void> _closeWeek(ShoppingListService service, ShoppingListResult result) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Woche abschließen?'),
            content: const Text(
              'Dabei wird Pantry-Verbrauch gebucht und Restmengen aus den gekauften Packungen in die Pantry übernommen.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abschließen')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    await service.applyToPantry(
      result: result,
      includeLine: (_) => true,
      consumePantryUsed: true,
      addLeftovers: true,
    );

    // optional: UI-Status zurücksetzen
    setState(() {
      checked.clear();
    });
    await _savePrefs();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Woche abgeschlossen – Pantry aktualisiert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ShoppingListService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einkaufsliste'),
        actions: [
          IconButton(
            tooltip: shoppingMode ? 'Planungsmodus' : 'Einkaufsmodus',
            icon: Icon(shoppingMode ? Icons.checklist : Icons.shopping_cart),
            onPressed: () {
              setState(() => shoppingMode = !shoppingMode);
              _savePrefs();
            },
          ),
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.sort),
            onSelected: (mode) {
              setState(() => sortMode = mode);
              _savePrefs();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: SortMode.expensiveFirst, child: Text('Teuerste zuerst')),
              PopupMenuItem(value: SortMode.alphabetic, child: Text('Alphabetisch (A–Z)')),
              PopupMenuItem(value: SortMode.bioFirst, child: Text('BIO zuerst')),
            ],
          ),
          if (shoppingMode)
            IconButton(
              tooltip: 'Alle Häkchen entfernen',
              icon: const Icon(Icons.refresh),
              onPressed: checked.isEmpty
                  ? null
                  : () {
                      setState(() => checked.clear());
                      _savePrefs();
                    },
            ),
          IconButton(
            tooltip: 'Reset (alles)',
            icon: const Icon(Icons.delete_outline),
            onPressed: _resetAll,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _prefsInitFuture,
        builder: (context, prefSnap) {
          if (prefSnap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (prefSnap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Prefs-Fehler: ${prefSnap.error}'),
            );
          }

          return FutureBuilder<ShoppingListResult>(
            future: service.buildFromWeekPlan(
              weekPlan: widget.weekPlan,
              people: widget.people,
              usePantry: true, // ✅ Pantry-Abzug aktiv
            ),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Fehler: ${snap.error}'),
                );
              }

              final result = snap.data!;
              final linesSorted = _sortedLines(result.lines);

              final totals = _computeTotals(result.lines);
              final totalCostCents = totals.$1;
              final bioCostCents = totals.$2;

              final plannedEuro = totalCostCents / 100.0;
              final diffEuro = plannedEuro - widget.budgetEuro;
              final bioSharePercent =
                  totalCostCents == 0 ? 0 : ((bioCostCents / totalCostCents) * 100).round();

              final totalItems = linesSorted.length;
              final doneItems = checked.length.clamp(0, totalItems);

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _modeBanner(),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Budget: €${widget.budgetEuro.toStringAsFixed(0)}'),
                                      Text('Geplant: €${plannedEuro.toStringAsFixed(2)}'),
                                      Text(
                                        'Differenz: ${diffEuro >= 0 ? "+" : ""}€${diffEuro.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: diffEuro > 0 ? Colors.red : Colors.green,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Bio-Anteil (Ist): $bioSharePercent%  •  Bio-Ziel: ${widget.bioTargetPercent}%',
                                      ),
                                      if (shoppingMode) ...[
                                        const SizedBox(height: 6),
                                        Text('Erledigt: $doneItems / $totalItems'),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(
                                        'Sortierung: ${_sortLabel()}',
                                        style: const TextStyle(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Liste kopieren',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () => _copyToClipboard(
                                    totalCostCents: totalCostCents,
                                    bioCostCents: bioCostCents,
                                    lines: linesSorted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              shoppingMode
                                  ? 'Tipp: Abhaken im Laden. BIO/KONV ist jetzt fix.'
                                  : 'Tipp: Pro Zutat BIO/KONV umschalten – Budget & Bio-Anteil werden live neu berechnet.',
                              style: const TextStyle(color: Colors.black54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: linesSorted.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final line = linesSorted[i];

                          final key = _lineKey(line);
                          final isChecked = checked.contains(key);

                          final selectedBio = _selectedBio(line) && line.canUseBio;
                          final badgeText = selectedBio ? 'BIO' : 'KONV';
                          final badgeColor = selectedBio ? Colors.green : Colors.grey;

                          final infoLines = <String>[
                            line.neededText(),
                            line.purchaseText(),
                            if ((_selectedBio(line) == true) && !line.canUseBio)
                              'Bio nicht verfügbar → Konv.',
                          ];

                          final titleStyle = TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            decoration: shoppingMode && isChecked ? TextDecoration.lineThrough : null,
                            color: shoppingMode && isChecked ? Colors.black45 : Colors.black87,
                          );

                          final totalEuro = line.totalEuro(selectedBio);
                          final packsEuro = line.packsEuro(selectedBio);

                          return InkWell(
                            onTap: !shoppingMode
                                ? null
                                : () {
                                    setState(() {
                                      if (isChecked) {
                                        checked.remove(key);
                                      } else {
                                        checked.add(key);
                                      }
                                    });
                                    _savePrefs();
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (shoppingMode)
                                    Checkbox(
                                      value: isChecked,
                                      onChanged: (_) {
                                        setState(() {
                                          if (isChecked) {
                                            checked.remove(key);
                                          } else {
                                            checked.add(key);
                                          }
                                        });
                                        _savePrefs();
                                      },
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(line.name, style: titleStyle),
                                        const SizedBox(height: 6),
                                        ...infoLines.map(
                                          (t) => Padding(
                                            padding: const EdgeInsets.only(bottom: 2),
                                            child: Text(
                                              t,
                                              style: TextStyle(
                                                color: shoppingMode && isChecked
                                                    ? Colors.black45
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: _bioKonvToggle(line),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 110,
                                    child: Opacity(
                                      opacity: shoppingMode && isChecked ? 0.5 : 1.0,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badgeColor.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                            child: Text(
                                              badgeText,
                                              style: TextStyle(
                                                color: badgeColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            totalEuro,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          Text(
                                            packsEuro,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ✅ Pantry Buttons
                    SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          if (shoppingMode) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.kitchen_outlined),
                                label: Text('Gekauftes → Pantry (${checked.length})'),
                                onPressed: checked.isEmpty
                                    ? null
                                    : () => _applyBoughtToPantry(service, result),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.done_all),
                              label: const Text('Woche abschließen'),
                              onPressed: () => _closeWeek(service, result),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}