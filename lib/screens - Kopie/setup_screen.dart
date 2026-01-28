import 'package:flutter/material.dart';
import 'plan_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _budgetController = TextEditingController(text: '50');
  final _peopleController = TextEditingController(text: '1');

  double bioPercent = 50;
  bool showRecipes = true;
String diet = 'omnivore'; // omnivore | vegetarian | vegan
int mealsPerDay = 3; // 1..3

  @override
  void dispose() {
    _budgetController.dispose();
    _peopleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BudgetBite Bio – Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Wochenbudget (€)'),
            const SizedBox(height: 6),
            TextField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'z.B. 50',
              ),
            ),
            const SizedBox(height: 16),

            const Text('Personenanzahl'),
            const SizedBox(height: 6),
            TextField(
              controller: _peopleController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'z.B. 1, 2, 4',
              ),
            ),
const Text('Ernährungsweise'),
const SizedBox(height: 6),

RadioListTile<String>(
  title: const Text('Mit Fleisch / Fisch'),
  value: 'omnivore',
  groupValue: diet,
  onChanged: (v) => setState(() => diet = v!),
),
RadioListTile<String>(
  title: const Text('Vegetarisch'),
  value: 'vegetarian',
  groupValue: diet,
  onChanged: (v) => setState(() => diet = v!),
),
RadioListTile<String>(
  title: const Text('Vegan'),
  value: 'vegan',
  groupValue: diet,
  onChanged: (v) => setState(() => diet = v!),
),

const SizedBox(height: 16),

            const SizedBox(height: 16),

            Text('Bio-Anteil (EU-Öko) Ziel: ${bioPercent.round()}%'),
            Slider(
              value: bioPercent,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${bioPercent.round()}%',
              onChanged: (v) => setState(() => bioPercent = v),
            ),
const SizedBox(height: 16),

Text('Mahlzeiten pro Tag: $mealsPerDay'),
Slider(
  value: mealsPerDay.toDouble(),
  min: 1,
  max: 3,
  divisions: 2,
  label: '$mealsPerDay',
  onChanged: (v) => setState(() => mealsPerDay = v.round()),
),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rezepte anzeigen'),
              value: showRecipes,
              onChanged: (v) => setState(() => showRecipes = v),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final budget = double.tryParse(_budgetController.text.trim());
                  final people = int.tryParse(_peopleController.text.trim());

                  if (budget == null || budget <= 0 || people == null || people <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bitte Budget und Personen korrekt eingeben.')),
                    );
                    return;
                  }

                  Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => PlanScreen(
      budgetEuro: budget,
      people: people,
      bioTargetPercent: bioPercent.round(),
      showRecipes: showRecipes,
diet: diet,
mealsPerDay: mealsPerDay,
    ),
  ),
);
                },
                child: const Text('Essensplan erstellen'),
              ),
            )
          ],
        ),
      ),
    );
  }
}
