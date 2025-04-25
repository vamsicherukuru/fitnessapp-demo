import 'package:flutter/material.dart';
import 'summary_screen.dart';

class GoalScreen extends StatefulWidget {
  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  String activity = '';
  String goal = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Lifestyle")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Activity Level"),
            DropdownButton<String>(
              value: activity.isNotEmpty ? activity : null,
              hint: Text("Select"),
              items:
                  ["Sedentary", "Light", "Active", "Intense"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
              onChanged: (value) => setState(() => activity = value!),
            ),
            SizedBox(height: 20),
            Text("Goal"),
            DropdownButton<String>(
              value: goal.isNotEmpty ? goal : null,
              hint: Text("Select"),
              items:
                  ["Lose Fat", "Gain Muscle", "Maintain"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
              onChanged: (value) => setState(() => goal = value!),
            ),
            Spacer(),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SummaryScreen()),
                );
              },
              child: Text("See Suggestion"),
            ),
          ],
        ),
      ),
    );
  }
}
