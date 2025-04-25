import 'package:flutter/material.dart';
import 'analyzing_screen.dart';

class SummaryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Dummy suggestion based on ideal condition
    String suggestion =
        "Based on your stats, we suggest losing 5kg for a healthier BMI.";

    return Scaffold(
      appBar: AppBar(title: Text("Summary")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              "Here’s your ideal condition:",
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),
            Text(suggestion),
            Spacer(),
            ElevatedButton(
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AnalyzingScreen()),
                  ),
              child: Text("Looks Good →"),
            ),
            TextButton(
              onPressed:
                  () => Navigator.popUntil(context, (route) => route.isFirst),
              child: Text("Re-enter Details"),
            ),
          ],
        ),
      ),
    );
  }
}
