import 'dart:async';
import 'package:flutter/material.dart';

class StoryViewScreen extends StatefulWidget {
  final String name;
  final String dp;

  const StoryViewScreen({required this.name, required this.dp});

  @override
  State<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends State<StoryViewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _zoomAnimation;
  late TextEditingController _replyController;

  @override
  void initState() {
    super.initState();

    _replyController = TextEditingController();

    // Auto close after 5 seconds
    Timer(Duration(seconds: 5), () {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    });

    // Zoom-in effect
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 700),
    );

    _zoomAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Full screen zoom image
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _zoomAnimation,
              builder:
                  (context, child) => Transform.scale(
                    scale: _zoomAnimation.value,
                    child: Image.asset(widget.dp, fit: BoxFit.cover),
                  ),
            ),
          ),

          // Progress bar
          Positioned(
            top: 40,
            left: 10,
            right: 10,
            child: LinearProgressIndicator(
              value: null,
              backgroundColor: Colors.white24,
              color: Colors.orange,
              minHeight: 4,
            ),
          ),

          // Name & profile
          Positioned(
            top: 50,
            left: 16,
            child: Row(
              children: [
                CircleAvatar(backgroundImage: AssetImage(widget.dp)),
                SizedBox(width: 10),
                Text(
                  widget.name,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),

          // Close button
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Reply field
          Positioned(
            left: 16,
            right: 16,
            bottom: 30,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Send a reply...",
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                      onTap: () {
                        // cancel auto-close on keyboard open
                        if (_controller.isAnimating) _controller.stop();
                      },
                    ),
                  ),
                  Icon(Icons.send, color: Colors.orangeAccent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
