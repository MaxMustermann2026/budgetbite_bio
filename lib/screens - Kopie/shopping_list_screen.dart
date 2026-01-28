import 'package:flutter/material.dart';
import '../services/shopping_list_service.dart';

class ShoppingListScreen extends StatefulWidget {
  final dynamic weekPlan;
  final int people;
  final double? budgetEuro;

  const ShoppingListScreen({
    super.key,
    required this.weekPlan,
    required this.people,
    this.budgetEuro,
  });

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  late Future<ShoppingListResult> _future;

  @override
  void initState() {
    super.initState();
    _future =
        ShoppingListService.buildFromWeekPlan(widget.weekPlan, widget.people);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einkaufsliste')),
      body: FutureBuilder<ShoppingListResult>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final result = snapshot.data!;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Total: ${(result.totalCostCents / 100).toStringAsFixed(2)} € '
                  '(BIO ${(result.totalBioCostCents / 100).toStringAsFixed(2)} €, '
                  'KONV ${(result.totalConvCostCents / 100).toStringAsFixed(2)} €)',
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: result.lines.length,
                  itemBuilder: (context, i) {
                    final line = result.lines[i];
                    return ListTile(
                      title: Text(line.name),
                      subtitle: Text(
                        'Benötigt: ${line.requiredAmount} ${line.unit}'
                        '${line.pantryUsed > 0 ? ' (Pantry -${line.pantryUsed})' : ''}',
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () async {
                    await ShoppingListService.applyResultToPantry(
                      result,
                      takeIntoPantryFilter: (_) => true,
                    );

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pantry aktualisiert'),
                      ),
                    );
                  },
                  child: const Text('In Pantry übernehmen'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}