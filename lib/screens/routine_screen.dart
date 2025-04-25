import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pedometer/pedometer.dart';
import 'package:flutter/services.dart';

class RoutineScreen extends StatefulWidget {
  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  List<Map<String, dynamic>> routineTasks = [];
  bool loading = true;
  int currentStreak = 0;
  String? userName;
  int stepCount = 0;
  int initialStepsToday = 0;
  bool initialStepSet = false;

  Stream<StepCount>? _stepCountStream;

  DateTime? lastCompletedDate;
  DateTime? streakEvaluatedDate;
  String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final Map<String, IconData> iconMap = {
    'wb_sunny_outlined': Icons.wb_sunny_outlined,
    'water_drop_outlined': Icons.water_drop_outlined,
    'free_breakfast_outlined': Icons.free_breakfast_outlined,
    'fitness_center_outlined': Icons.fitness_center_outlined,
    'rice_bowl_outlined': Icons.rice_bowl_outlined,
    'restaurant_menu': Icons.restaurant_menu,
    'nightlight_round': Icons.nightlight_round,
  };
  bool isMissedStrictTask(Map<String, dynamic> task) {
    if ((task['type'] ?? 'flexible') != 'strict') return false;
    if (task['done'] == true) return false;
    if (task['endTime'] == null) return false;

    final now = TimeOfDay.now();
    final endParts = task['endTime'].split(":").map(int.parse).toList();
    final end = TimeOfDay(hour: endParts[0], minute: endParts[1]);

    return now.hour > end.hour ||
        (now.hour == end.hour && now.minute > end.minute);
  }

  bool _isCurrentTimeWithin(String start, String? end) {
    final now = TimeOfDay.now();
    final startParts = start.split(":").map(int.parse).toList();
    final startTime = TimeOfDay(hour: startParts[0], minute: startParts[1]);

    final isAfterStart =
        now.hour > startTime.hour ||
        (now.hour == startTime.hour && now.minute >= startTime.minute);

    if (end == null) return isAfterStart;

    final endParts = end.split(":").map(int.parse).toList();
    final endTime = TimeOfDay(hour: endParts[0], minute: endParts[1]);

    final isBeforeEnd =
        now.hour < endTime.hour ||
        (now.hour == endTime.hour && now.minute <= endTime.minute);

    return isAfterStart && isBeforeEnd;
  }

  bool canTickTask(Map<String, dynamic> task) {
    final type = task['type'] ?? 'flexible';
    if (type == 'flexible') return true;

    final start = task['startTime'] ?? '00:00';
    final end = task['endTime'];
    return _isCurrentTimeWithin(start, type == 'strict' ? end : null);
  }

  @override
  void initState() {
    super.initState();
    loadUserRoutine();
    initPedometer();
  }

  Future<void> loadTodaySteps(String uid) async {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final doc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('dailySteps')
            .doc(todayKey)
            .get();

    if (doc.exists) {
      final data = doc.data();
      setState(() {
        stepCount = data?['steps'] ?? 0;
      });
    }
  }

  void initPedometer() {
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountStream?.listen(onStepCount).onError(onStepCountError);
  }

  void onStepCount(StepCount event) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailySteps')
        .doc(todayKey);

    final snapshot = await docRef.get();

    // Fetch or set initial step value
    if (!snapshot.exists || snapshot.data()?['initialSteps'] == null) {
      await docRef.set({
        'initialSteps': event.steps,
        'steps': 0,
        'updatedAt': Timestamp.now(),
      });
      initialStepsToday = event.steps;
    } else {
      initialStepsToday = snapshot.data()?['initialSteps'] ?? event.steps;
    }

    final stepsToday = event.steps - initialStepsToday;
    final cleanSteps = stepsToday < 0 ? 0 : stepsToday;

    setState(() {
      stepCount = cleanSteps;
    });

    // Update Firebase with live steps
    await docRef.set({
      'steps': cleanSteps,
      'updatedAt': Timestamp.now(),
      'initialSteps': initialStepsToday, // just in case
    }, SetOptions(merge: true));
  }

  void onStepCountError(error) {
    print('Step Count Error: $error');
  }

  String getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning";
    if (hour < 16) return "Good Afternoon";
    if (hour < 20) return "Good Evening";
    return "Good Night";
  }

  Future<void> loadUserRoutine() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docSnapshot =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (!docSnapshot.exists) {
      setState(() => loading = false);
      return;
    }

    final data = docSnapshot.data()!;

    userName = data['name'] ?? "User"; //ADD THIS

    if (uid == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        setState(() => loading = false);
        return;
      }

      final data = userDoc.data()!;
      final goal = data['goal'] ?? "Lose Fat";
      final age = data['age'] ?? 25;
      final gender = data['gender'] ?? "Male";
      final activityLevel = data['activityLevel'] ?? "Moderate";
      currentStreak = data['currentStreak'] ?? 0;
      lastCompletedDate = (data['lastCompletedDate'] as Timestamp?)?.toDate();
      streakEvaluatedDate =
          (data['streakEvaluatedDate'] as Timestamp?)?.toDate();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      // 🔥 Streak update logic
      if (lastCompletedDate != null &&
          lastCompletedDate!.isAtSameMomentAs(yesterday) &&
          (streakEvaluatedDate == null ||
              streakEvaluatedDate!.isBefore(today))) {
        currentStreak++;
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'currentStreak': currentStreak,
          'streakEvaluatedDate': Timestamp.fromDate(today),
        });
      }

      // 🔁 Load today's tasks (persisted)
      final taskSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('routines')
              .doc(todayKey)
              .get();

      if (taskSnapshot.exists) {
        final savedTasks = List<Map<String, dynamic>>.from(
          taskSnapshot.data()?['tasks'] ?? [],
        );
        setState(() {
          routineTasks = savedTasks;
          loading = false;
        });
      } else {
        final defaultTasks = generateRoutine(
          goal: goal,
          age: age,
          gender: gender,
          activityLevel: activityLevel,
        );
        setState(() {
          routineTasks = defaultTasks;
          loading = false;
        });
        await saveRoutineTasksToFirestore(defaultTasks);
      }
    } catch (e) {
      print("Routine fetch error: $e");
      setState(() => loading = false);
    }

    await loadTodaySteps(uid);
  }

  Future<void> saveRoutineTasksToFirestore(
    List<Map<String, dynamic>> tasks,
  ) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('routines')
        .doc(todayKey)
        .set({'tasks': tasks});
  }

  Future<void> updateTaskState(int index, bool value) async {
    setState(() {
      routineTasks[index]["done"] = value;
    });

    await saveRoutineTasksToFirestore(routineTasks);
    await updateCompletionDateIfDone();
  }

  Future<void> updateCompletionDateIfDone() async {
    final allDone = routineTasks.every((task) => task["done"] == true);
    if (!allDone) return;

    // 🧠 Always show alert on 100% completion — no restrictions
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Beast Mode Activated 🔥"),
            content: const Text(
              "You’ve completed all tasks for today. If you keep this till midnight, your streak will grow tomorrow.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Got it"),
              ),
            ],
          ),
    );

    // Still update lastCompletedDate for streak calculation
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'lastCompletedDate': Timestamp.fromDate(today),
    });

    setState(() {
      lastCompletedDate = today;
    });
  }

  List<Map<String, dynamic>> generateRoutine({
    required String goal,
    required int age,
    required String gender,
    required String activityLevel,
  }) {
    return [
      {
        "title": "Morning Routine",
        "subtitle": "Wake up, freshen up, light stretch",
        "icon": "wb_sunny_outlined",
        "done": false,
        "type": "strict",
        "startTime": "04:00",
        "endTime": "09:00",
      },
      {
        "title": "Hydration",
        "subtitle": "Drink 8 glasses of water",
        "icon": "water_drop_outlined",
        "done": false,
        "type": "flexible",
      },
      {
        "title": "Breakfast",
        "subtitle": "Oats + Almond milk + Banana",
        "icon": "free_breakfast_outlined",
        "done": false,
        "type": "strict",
        "startTime": "06:30",
        "endTime": "10:00",
      },
      {
        "title": "Workout",
        "subtitle":
            goal == "Lose Fat"
                ? "HIIT + Cardio (30 mins)"
                : goal == "Build Muscle"
                ? "Strength: Chest + Triceps (45 mins)"
                : "Walk + Light Yoga (20 mins)",
        "icon": "fitness_center_outlined",
        "done": false,
        "type": "flexible",
      },
      {
        "title": "Lunch",
        "subtitle": "Brown rice + Dal + Veggies",
        "icon": "rice_bowl_outlined",
        "done": false,
        "type": "strict",
        "startTime": "12:00",
        "endTime": "15:00",
      },
      {
        "title": "Dinner",
        "subtitle":
            gender == "Male" ? "Grilled Chicken + Salad" : "Paneer + Broccoli",
        "icon": "restaurant_menu",
        "done": false,
        "type": "strict",
        "startTime": "18:00",
        "endTime": "21:00",
      },
      {
        "title": "Sleep Time",
        "subtitle": "Target: 10:30 PM",
        "icon": "nightlight_round",
        "done": false,
        "type": "semi-strict",
        "startTime": "18:30",
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final todayFormatted = DateFormat('EEEE, MMM d').format(DateTime.now());
    final completed = routineTasks.where((task) => task["done"]).length;
    final progress = routineTasks.isEmpty ? 0 : completed / routineTasks.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Your Routine",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                Icon(Icons.local_fire_department, color: Colors.deepOrange),
                const SizedBox(width: 4),
                Text(
                  "$currentStreak-day",
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body:
          loading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
              : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Text(
                      "${getTimeBasedGreeting()}, ${userName ?? ''} 👋",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      todayFormatted,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: progress.toDouble(),
                      backgroundColor: Colors.grey.shade200,
                      color: Colors.deepOrange,
                      minHeight: 6,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Routine progress: ${(progress * 100).toStringAsFixed(0)}%",
                      style: const TextStyle(
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.2,
                            ),
                        itemCount: routineTasks.length,
                        itemBuilder: (context, index) {
                          final task = routineTasks[index];
                          final isDone = task['done'];
                          final isMissed = isMissedStrictTask(task);

                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              if (canTickTask(task)) {
                                updateTaskState(index, !isDone);
                              } else {
                                final type = task['type'] ?? 'flexible';
                                final start = task['startTime'] ?? '--:--';
                                final end = task['endTime'] ?? '--:--';

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      type == 'strict'
                                          ? "⏰ '${task['title']}' allowed only between $start–$end"
                                          : "⏰ '${task['title']}' is only available after $start",
                                    ),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },

                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: 0,
                                end: isDone ? 1 : 0,
                              ),
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.elasticOut,
                              builder: (context, value, child) {
                                return Transform.rotate(
                                  angle: value * 0.01, // Wobble effect
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                    decoration: BoxDecoration(
                                      color:
                                          isDone
                                              ? Colors.green.withOpacity(0.1)
                                              : Theme.of(context).cardColor,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        if (isDone)
                                          BoxShadow(
                                            color: Colors.greenAccent
                                                .withOpacity(0.4),
                                            blurRadius: 16,
                                            spreadRadius: 2,
                                            offset: const Offset(0, 3),
                                          )
                                        else
                                          BoxShadow(
                                            color: Colors.grey.withOpacity(0.2),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                      ],
                                      border: Border.all(
                                        color:
                                            isDone
                                                ? Colors.green
                                                : Colors.grey.shade300,
                                        width: 2,
                                      ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              iconMap[task['icon']] ??
                                                  Icons.help_outline,
                                              size: 32,
                                              color:
                                                  isDone
                                                      ? Colors.green
                                                      : Colors.deepOrangeAccent,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              task['title'],
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color:
                                                    isDone
                                                        ? Colors.green.shade800
                                                        : Theme.of(context)
                                                            .textTheme
                                                            .bodyLarge!
                                                            .color,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              task['subtitle'],
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),

                                        // ✅ TICK WITH GLOW & PULSE
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 500,
                                          ),
                                          switchInCurve: Curves.elasticOut,
                                          switchOutCurve: Curves.easeInOut,
                                          transitionBuilder:
                                              (child, anim) => ScaleTransition(
                                                scale: anim,
                                                child: child,
                                              ),
                                          child:
                                              isDone
                                                  ? Container(
                                                    key: const ValueKey(true),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.green
                                                              .withOpacity(0.5),
                                                          blurRadius: 20,
                                                          spreadRadius: 1,
                                                        ),
                                                      ],
                                                      color: Colors.green,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    child: const Icon(
                                                      Icons.check,
                                                      size: 30,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                  : const SizedBox.shrink(
                                                    key: ValueKey(false),
                                                  ),
                                        ),

                                        // ❌ MISSED STAMP
                                        if (isMissed)
                                          Positioned(
                                            top: 12,
                                            right: 12,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.redAccent
                                                    .withOpacity(0.9),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                "MISSED",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            "Step Count",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "$stepCount",
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "\"One tick at a time, you're building a beast.\"",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
    );
  }
}
