import 'package:flutter/material.dart';
import 'stats_screen.dart';

class NameGenderScreen extends StatefulWidget {
  @override
  State<NameGenderScreen> createState() => _NameGenderScreenState();
}

class _NameGenderScreenState extends State<NameGenderScreen> {
  String name = '';
  String gender = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Let's Get Started")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(labelText: "Your Name"),
              onChanged: (value) => name = value,
            ),
            SizedBox(height: 20),
            Text("Select Gender"),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ChoiceChip(
                  label: Text("👦 Male"),
                  selected: gender == 'Male',
                  onSelected: (_) => setState(() => gender = 'Male'),
                ),
                ChoiceChip(
                  label: Text("👧 Female"),
                  selected: gender == 'Female',
                  onSelected: (_) => setState(() => gender = 'Female'),
                ),
                ChoiceChip(
                  label: Text("🧑 Other"),
                  selected: gender == 'Other',
                  onSelected: (_) => setState(() => gender = 'Other'),
                ),
              ],
            ),
            Spacer(),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => StatsScreen()),
                );
              },
              child: Text("Next"),
            ),
          ],
        ),
      ),
    );
  }
}
