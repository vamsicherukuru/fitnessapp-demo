// lib/screens/routine_screen.dart
//
// Add in pubspec.yaml
//   pedometer: ^2.1.3
// ─────────────────────────────────────────────────────────────
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pedometer/pedometer.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key});
  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  /* ───────── state ───────── */
  List<Map<String, dynamic>> routineTasks = [];
  bool loading = true;
  int currentStreak = 0;
  String? userName;

  int stepCount = 0;
  int initialStepsToday = 0;
  Stream<StepCount>? _stepStream;

  final String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

  final Map<String, IconData> iconMap = {
    'wb_sunny_outlined': Icons.wb_sunny_outlined,
    'water_drop_outlined': Icons.water_drop_outlined,
    'free_breakfast_outlined': Icons.free_breakfast_outlined,
    'fitness_center_outlined': Icons.fitness_center_outlined,
    'rice_bowl_outlined': Icons.rice_bowl_outlined,
    'restaurant_menu': Icons.restaurant_menu,
    'nightlight_round': Icons.nightlight_round,
  };

  /* ───────── time helpers ───────── */
  bool _isCurrentTimeWithin(String start, String? end) {
    final now = TimeOfDay.now();
    final s = start.split(':').map(int.parse).toList();
    final st = TimeOfDay(hour: s[0], minute: s[1]);
    final after =
        now.hour > st.hour || (now.hour == st.hour && now.minute >= st.minute);

    if (end == null) return after;
    final e = end.split(':').map(int.parse).toList();
    final et = TimeOfDay(hour: e[0], minute: e[1]);
    final before =
        now.hour < et.hour || (now.hour == et.hour && now.minute <= et.minute);

    return after && before;
  }

  bool _canTick(Map<String, dynamic> t) {
    final type = t['type'] ?? 'flexible';
    if (type == 'flexible') return true;
    return _isCurrentTimeWithin(
      t['startTime'] ?? '00:00',
      type == 'strict' ? t['endTime'] : null,
    );
  }

  bool _isMissedStrict(Map<String, dynamic> t) {
    if ((t['type'] ?? 'flexible') != 'strict' || t['done'] == true)
      return false;
    final end = t['endTime'];
    if (end == null) return false;

    final now = TimeOfDay.now();
    final p = end.split(':').map(int.parse).toList();
    final et = TimeOfDay(hour: p[0], minute: p[1]);
    return now.hour > et.hour ||
        (now.hour == et.hour && now.minute > et.minute);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 16) return 'Good afternoon';
    if (h < 20) return 'Good evening';
    return 'Good night';
  }

  /* ───────── init ───────── */
  @override
  void initState() {
    super.initState();
    _loadSteps(); // cached steps first
    _loadRoutine(); // then tasks & user doc
    _initPedometer(); // then live pedometer
  }

  /* ───────── pedometer ───────── */
  void _initPedometer() {
    _stepStream = Pedometer.stepCountStream;
    _stepStream
        ?.listen(_onStep)
        .onError((e) => debugPrint('Pedometer error → $e'));
  }

  void _onStep(StepCount ev) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailySteps')
        .doc(todayKey);
    final snap = await ref.get();

    if (!snap.exists || snap.data()?['initialSteps'] == null) {
      await ref.set({
        'initialSteps': ev.steps,
        'steps': 0,
        'updatedAt': Timestamp.now(),
      });
      initialStepsToday = ev.steps;
    } else {
      initialStepsToday = snap['initialSteps'] ?? ev.steps;
    }

    setState(() => stepCount = (ev.steps - initialStepsToday).clamp(0, 100000));
    ref.set({
      'steps': stepCount,
      'updatedAt': Timestamp.now(),
      'initialSteps': initialStepsToday,
    }, SetOptions(merge: true));
  }

  /* ───────── firestore: steps ───────── */
  Future<void> _loadSteps() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('dailySteps')
            .doc(todayKey)
            .get();
    if (doc.exists) {
      setState(() => stepCount = doc['steps'] ?? 0);
      initialStepsToday = doc['initialSteps'] ?? 0;
    }
  }

  /* ───────── firestore: routine & user ───────── */
  Future<void> _loadRoutine() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => loading = false);
      return;
    }

    try {
      /* user doc */
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final user = userSnap.data() ?? {};
      userName = user['name'] ?? 'User';
      currentStreak = user['currentStreak'] ?? 0;

      /* today’s routine */
      final rSnap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('routines')
              .doc(todayKey)
              .get();

      if (rSnap.exists) {
        routineTasks = List<Map<String, dynamic>>.from(rSnap['tasks'] ?? []);
        final changed = _syncTasksWithDefault(user, removeObsolete: true);
        if (changed) await _saveTasks();
      } else {
        routineTasks = _defaultRoutine(user);
        await _saveTasks();
      }
    } catch (e) {
      debugPrint('Routine load error → $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /* ---------- default template ---------- */
  List<Map<String, dynamic>> _defaultRoutine(Map<String, dynamic> u) => [
    {
      'title': 'Morning Routine',
      'subtitle': 'Wake • stretch',
      'icon': 'wb_sunny_outlined',
      'done': false,
      'type': 'flexible',
      'startTime': '04:00',
      'endTime': '09:00',
    },
    {
      'title': 'Hydration',
      'subtitle': '8 glasses',
      'icon': 'water_drop_outlined',
      'done': false,
      'type': 'flexible',
    },
    {
      'title': 'Breakfast',
      'subtitle': 'Oats + fruit',
      'icon': 'free_breakfast_outlined',
      'done': false,
      'type': 'flexible',
      'startTime': '06:30',
      'endTime': '11:30',
    },
    {
      'title': 'Workout',
      'subtitle':
          (u['goal'] ?? 'Lose Fat') == 'Lose Fat'
              ? 'HIIT 30 m'
              : 'Strength 45 m',
      'icon': 'fitness_center_outlined',
      'done': false,
      'type': 'flexible',
    },
    {
      'title': 'Lunch',
      'subtitle': 'Healthy plate',
      'icon': 'rice_bowl_outlined',
      'done': false,
      'type': 'strict',
      'startTime': '12:00',
      'endTime': '15:00',
    },
    {
      'title': 'Dinner',
      'subtitle':
          (u['gender'] ?? 'Male') == 'Male' ? 'Chicken + veg' : 'Paneer + veg',
      'icon': 'restaurant_menu',
      'done': false,
      'type': 'strict',
      'startTime': '18:00',
      'endTime': '21:00',
    },
    {
      'title': 'Sleep',
      'subtitle': 'Target 22:30',
      'icon': 'nightlight_round',
      'done': false,
      'type': 'semi-strict',
      'startTime': '18:30',
    },
  ];

  /* ---------- merge stored tasks with template ---------- */
  bool _syncTasksWithDefault(
    Map<String, dynamic> user, {
    bool removeObsolete = false,
  }) {
    final latest = _defaultRoutine(user);
    final mapLatest = {for (final t in latest) t['title']: t};
    final mapExisting = {for (final t in routineTasks) t['title']: t};

    var dirty = false;

    // add or update
    for (final entry in mapLatest.entries) {
      if (!mapExisting.containsKey(entry.key)) {
        routineTasks.add({...entry.value});
        dirty = true;
      } else {
        final stored = mapExisting[entry.key]!;
        for (final k in entry.value.keys) {
          if (k == 'done') continue;
          if (stored[k] != entry.value[k]) {
            stored[k] = entry.value[k];
            dirty = true;
          }
        }
      }
    }

    // optionally remove obsolete tasks
    if (removeObsolete) {
      routineTasks.removeWhere((t) => !mapLatest.containsKey(t['title']));
      dirty = true;
    }
    return dirty;
  }

  /* ---------- save ---------- */
  Future<void> _saveTasks() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('routines')
        .doc(todayKey)
        .set({'tasks': routineTasks});
  }

  /* ───────── interactions ───────── */
  Future<void> _onTaskTap(int idx) async {
    final t = routineTasks[idx];
    if (!_canTick(t)) {
      _showSnack(
        '⏰  This task is available only between ${t['startTime']} – ${t['endTime']}',
      );
      return;
    }

    routineTasks[idx]['done'] = !(t['done'] as bool);
    setState(() {});
    await _saveTasks();
    _checkIfAllDone();
  }

  void _showSnack(String msg) {
    final m = ScaffoldMessenger.of(context);
    m
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          content: Text(msg),
        ),
      );
  }

  Future<void> _checkIfAllDone() async {
    if (!routineTasks.every((t) => t['done'] == true)) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'lastCompletedDate': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));

    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Beast mode! 🔥'),
            content: const Text(
              'All tasks finished! Keep it up till midnight to grow your streak.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  /* ───────── ui ───────── */
  @override
  Widget build(BuildContext ctx) {
    final todayTxt = DateFormat('EEEE, MMM d').format(DateTime.now());
    final done = routineTasks.where((t) => t['done']).length;
    final prog = routineTasks.isEmpty ? 0.0 : done / routineTasks.length;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      drawer: const _AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.grey[50],
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Routine',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                children: [
                  Text(
                    '${_greeting()}, ${userName ?? ''} 👋',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(todayTxt, style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        color: Colors.deepOrange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$currentStreak-day streak',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Nutrition',
                          value: '900 / 1200 cal',
                          colour: Colors.deepPurple,
                          progress: 0.75,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _StatCard(
                          title: 'Water',
                          value: '5 / 8 cups',
                          colour: Colors.blue,
                          progress: 0.62,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _StatCard(
                    title: 'Routine',
                    value: '${(prog * 100).toStringAsFixed(0)} % done',
                    colour: Colors.deepOrange,
                    progress: prog,
                  ),
                  const SizedBox(height: 28),

                  _TaskGrid(
                    tasks: routineTasks,
                    iconMap: iconMap,
                    onTap: _onTaskTap,
                    isMissed: _isMissedStrict,
                  ),
                  const SizedBox(height: 30),

                  _StepsCircleCard(stepCount: stepCount),
                ],
              ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* ----------------------------- widgets below ------------------------------ */
/* -------------------------------------------------------------------------- */

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();
  @override
  Widget build(BuildContext ctx) => const Drawer(); // keep minimal
}

/* ───────── stat card ───────── */
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.progress,
    required this.colour,
  });
  final String title, value;
  final double progress;
  final Color colour;

  @override
  Widget build(BuildContext ctx) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: progress),
    duration: const Duration(milliseconds: 800),
    curve: Curves.easeOutCubic,
    builder:
        (_, val, __) => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: val,
                  minHeight: 8,
                  backgroundColor: Colors.grey[300],
                  color: colour,
                ),
              ),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
  );
}

/* ───────── task grid (centred layout) ───────── */
class _TaskGrid extends StatelessWidget {
  const _TaskGrid({
    required this.tasks,
    required this.iconMap,
    required this.onTap,
    required this.isMissed,
  });
  final List<Map<String, dynamic>> tasks;
  final Map<String, IconData> iconMap;
  final void Function(int) onTap;
  final bool Function(Map<String, dynamic>) isMissed;

  @override
  Widget build(BuildContext ctx) => GridView.builder(
    physics: const NeverScrollableScrollPhysics(),
    shrinkWrap: true,
    itemCount: tasks.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.05, // near-square card
    ),
    itemBuilder: (_, i) {
      final t = tasks[i];
      final done = t['done'] as bool;
      final missed = isMissed(t);

      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: done ? 1 : 0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.elasticOut,
        builder:
            (_, wobble, child) =>
                Transform.rotate(angle: wobble * 0.05, child: child),
        child: GestureDetector(
          onTap: () => onTap(i),
          child: AnimatedContainer(
            padding: const EdgeInsets.all(14),
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: done ? Colors.green.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: done ? Colors.green : Colors.grey[300]!,
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        iconMap[t['icon']] ?? Icons.help_outline,
                        size: 32,
                        color: done ? Colors.green : Colors.deepPurple,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t['title'],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: done ? Colors.green : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t['subtitle'],
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                if (missed)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'MISSED',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (done)
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/* ───────── steps circle ───────── */
class _StepsCircleCard extends StatelessWidget {
  const _StepsCircleCard({required this.stepCount});
  final int stepCount;

  @override
  Widget build(BuildContext ctx) {
    final pct = (stepCount / 10000).clamp(0.0, 1.0);
    final col =
        (pct == 1)
            ? Colors.green
            : pct > 0.4
            ? Colors.orange
            : Colors.grey[400]!;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Daily Steps',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 18),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder:
                (_, val, __) => CustomPaint(
                  painter: _CirclePainter(val, col),
                  size: const Size(140, 140),
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: Center(
                      child: Text(
                        '$stepCount',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
          ),
          const SizedBox(height: 14),
          Text(
            pct == 1 ? 'Goal reached! 🎉' : 'Goal: 10 000 steps',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  _CirclePainter(this.pct, this.col);
  final double pct;
  final Color col;
  @override
  void paint(Canvas c, Size s) {
    const stroke = 10.0;
    final centre = s.center(Offset.zero);
    final r = s.width / 2;

    final bg =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = Colors.grey[300]!
          ..strokeCap = StrokeCap.round;
    c.drawArc(
      Rect.fromCircle(center: centre, radius: r),
      -math.pi / 2,
      2 * math.pi,
      false,
      bg,
    );

    final fg =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = col
          ..strokeCap = StrokeCap.round;
    c.drawArc(
      Rect.fromCircle(center: centre, radius: r),
      -math.pi / 2,
      2 * math.pi * pct,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _CirclePainter old) =>
      old.pct != pct || old.col != col;
}
