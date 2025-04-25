import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/home_screen.dart';

class WelcomeScreen extends StatefulWidget {
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Form inputs
  String name = '';
  String gender = '';
  String age = '';
  String height = '';
  String weight = '';
  String activity = '';
  String goal = '';

  void _nextPage() {
    if (_currentIndex < 5) {
      _pageController.nextPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submitToFirestore();
    }
  }

  Future<void> _submitToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final docSnap = await docRef.get();

      final data = {
        'name': name,
        'gender': gender,
        'age': int.tryParse(age) ?? 0,
        'height': int.tryParse(height) ?? 0,
        'weight': int.tryParse(weight) ?? 0,
        'activity': activity,
        'goal': goal,
        'onboardingCompleted': true,
      };

      if (docSnap.exists) {
        await docRef.update(data);
      } else {
        await docRef.set(data);
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    }
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          child,
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: Text(_currentIndex == 5 ? "Finish" : "Next →"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: NeverScrollableScrollPhysics(),
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                'assets/lottie/fitness.json',
                height: size.height * 0.4,
              ),
              const SizedBox(height: 30),
              const Text(
                "Welcome to Hanumode",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Unleash your inner warrior",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                ),
                child: const Text("Let’s Go →", style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
          _buildCard(
            title: "What's your name?",
            child: TextField(
              onChanged: (val) => name = val,
              decoration: InputDecoration(hintText: "Enter your name"),
            ),
          ),
          _buildCard(
            title: "Select your gender",
            child: Wrap(
              spacing: 12,
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
          ),
          _buildCard(
            title: "Your age",
            child: TextField(
              keyboardType: TextInputType.number,
              onChanged: (val) => age = val,
              decoration: InputDecoration(hintText: "Enter age in years"),
            ),
          ),
          _buildCard(
            title: "Your height & weight",
            child: Column(
              children: [
                TextField(
                  keyboardType: TextInputType.number,
                  onChanged: (val) => height = val,
                  decoration: InputDecoration(hintText: "Height in cm"),
                ),
                const SizedBox(height: 12),
                TextField(
                  keyboardType: TextInputType.number,
                  onChanged: (val) => weight = val,
                  decoration: InputDecoration(hintText: "Weight in kg"),
                ),
              ],
            ),
          ),
          _buildCard(
            title: "Lifestyle & Goal",
            child: Column(
              children: [
                DropdownButton<String>(
                  value: activity.isNotEmpty ? activity : null,
                  hint: Text("Activity Level"),
                  items:
                      ["Sedentary", "Light", "Active", "Intense"]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (val) => setState(() => activity = val!),
                ),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  value: goal.isNotEmpty ? goal : null,
                  hint: Text("Fitness Goal"),
                  items:
                      ["Lose Fat", "Gain Muscle", "Maintain"]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (val) => setState(() => goal = val!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
