import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CalorieCheckScreen extends StatefulWidget {
  @override
  State<CalorieCheckScreen> createState() => _CalorieCheckScreenState();
}

class _CalorieCheckScreenState extends State<CalorieCheckScreen> {
  File? _image;
  bool _showResult = false;

  @override
  void initState() {
    super.initState();
    // Automatically open the camera after short delay (for smoother UX)
    Future.delayed(Duration(milliseconds: 400), () {
      _pickImage();
    });
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.camera,
    );
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _showResult = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          "Calorie Check",
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child:
              !_showResult
                  ? CircularProgressIndicator(color: Colors.deepOrange)
                  : Column(
                    children: [
                      SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.file(_image!, height: 200),
                      ),
                      SizedBox(height: 20),
                      Text(
                        "🍗 Grilled Chicken Plate",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "🔥 Estimated: 401 Calories",
                        style: TextStyle(
                          color: Colors.deepOrange,
                          fontSize: 16,
                        ),
                      ),
                      Divider(height: 30),
                      _nutrientTile(
                        "Protein",
                        "35g",
                        Icons.local_fire_department,
                        Colors.red,
                      ),
                      _nutrientTile("Carbs", "20g", Icons.cake, Colors.orange),
                      _nutrientTile(
                        "Fats",
                        "18g",
                        Icons.oil_barrel_outlined,
                        Colors.brown,
                      ),
                      Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _image = null;
                            _showResult = false;
                            _pickImage(); // reopen camera
                          });
                        },
                        child: Text("Scan Another"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade800,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 12,
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _nutrientTile(String label, String value, IconData icon, Color color) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
