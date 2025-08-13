import 'package:flutter/material.dart';

class MapsPage extends StatelessWidget {
  const MapsPage({super.key});

  Widget navItem(IconData icon, String label, {bool selected = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF8C52FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 250,
            color: const Color(0xFF1C1C1E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('images/logo.png', width: 40),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Text(
                        'MOH User',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 50),
                navItem(Icons.home, 'Home'),
                navItem(Icons.report_problem, 'Complaints'),
                navItem(Icons.analytics, 'Analytics'),
                navItem(Icons.map, 'Maps', selected: true),
              ],
            ),
          ),

          // Main Content
          const Expanded(
            child: Center(
              child: Text(
                'Maps Page Coming Soon...',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
