import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for HapticFeedback
import 'routine_screen.dart';
import 'calorie_check_screen.dart';
import 'friends_screen.dart';
import 'account_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _tabs = [
    RoutineScreen(),
    CalorieCheckScreen(),
    FriendsScreen(),
    AccountScreen(),
  ];

  void _onTabTapped(int index) {
    HapticFeedback.lightImpact(); // 💥 Give haptic feedback
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: Duration(milliseconds: 300), // ⏱ Smooth transition
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _tabs[_selectedIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.access_time),
            label: 'Routine',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Calorie'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Friends'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
