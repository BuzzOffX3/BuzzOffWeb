import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage({super.key});

  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  String username = 'Loading...';

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        setState(() {
          username = userDoc['username'] ?? 'User';
        });
      } else {
        setState(() {
          username = 'Unknown User';
        });
      }
    }
  }

  static const TextStyle headerStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
  );

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
                    Flexible(
                      child: Text(
                        username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 50),
                navItem(Icons.home, 'Home'),
                navItem(Icons.report_problem, 'Complaints', selected: true),
                navItem(Icons.analytics, 'Analytics'),
                navItem(Icons.map, 'Maps'),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          '"Complaints are not setbacks; they’re unfiltered insights that guide our evolution and strengthen our service."',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundImage: AssetImage('images/pfp.png'),
                            radius: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            username,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // Table Title & Submit Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Complaints Table',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          // TODO: Submit Logic
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8C52FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Submit'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Table Headers
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: const [
                        Expanded(flex: 1, child: Text('#', style: headerStyle)),
                        Expanded(
                          flex: 3,
                          child: Text('Name', style: headerStyle),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text('Description', style: headerStyle),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Image', style: headerStyle),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Map Link', style: headerStyle),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Date', style: headerStyle),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Time', style: headerStyle),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('Status', style: headerStyle),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 5),

                  // Complaints Table
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('complaints')
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text(
                                'No Complaints Found',
                                style: TextStyle(color: Colors.white),
                              ),
                            );
                          }

                          final complaints = snapshot.data!.docs;

                          return ListView.builder(
                            itemCount: complaints.length,
                            itemBuilder: (context, index) {
                              var data = complaints[index];
                              var isAnonymous = data['isAnonymous'] ?? true;
                              var userId = data['userId'] ?? '';

                              if (isAnonymous) {
                                return complaintRow(
                                  index: index,
                                  name: 'Anonymous',
                                  location: data['location'],
                                  description: data['description'],
                                  imageUrl: data['imageUrl'],
                                  timestamp: data['timestamp'],
                                );
                              } else {
                                return FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(userId)
                                      .get(),
                                  builder: (context, userSnapshot) {
                                    String displayName = 'Unknown User';

                                    if (userSnapshot.connectionState ==
                                            ConnectionState.done &&
                                        userSnapshot.hasData &&
                                        userSnapshot.data != null &&
                                        userSnapshot.data!.exists) {
                                      var userData =
                                          userSnapshot.data!.data()
                                              as Map<String, dynamic>;

                                      displayName =
                                          userData['name'] ??
                                          userData['username'] ??
                                          'Unknown User';
                                    }

                                    return complaintRow(
                                      index: index,
                                      name: displayName,
                                      location: data['location'],
                                      description: data['description'],
                                      imageUrl: data['imageUrl'],
                                      timestamp: data['timestamp'],
                                    );
                                  },
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Pagination Footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '1-10 of 97',
                        style: TextStyle(color: Colors.white),
                      ),
                      Row(
                        children: [
                          const Text(
                            'Rows per page: 10',
                            style: TextStyle(color: Colors.white),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 20),
                          const Text(
                            '1/10',
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.chevron_left,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.chevron_right,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget complaintRow({
    required int index,
    required String name,
    required String? location,
    required String? description,
    required String? imageUrl,
    required Timestamp? timestamp,
  }) {
    DateTime dateTime = timestamp != null ? timestamp.toDate() : DateTime.now();
    String dateStr = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    String timeStr = DateFormat('hh:mm a').format(dateTime);

    String selectedStatus = 'Pending';

    Color getStatusColor(String status) {
      switch (status) {
        case 'Pending':
          return Colors.orange;
        case 'Under Review':
          return Colors.blue;
        case 'Under Investigation':
          return Colors.red;
        case 'Reviewed':
          return Colors.green;
        default:
          return Colors.white;
      }
    }

    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: Row(
                  children: [
                    Checkbox(value: false, onChanged: (value) {}),
                    Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white)),
                    Text(
                      location ?? 'No Location',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  description ?? 'No Description',
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: imageUrl != null
                    ? Image.network(imageUrl, width: 40, height: 40)
                    : const Icon(Icons.image_not_supported, color: Colors.grey),
              ),
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () {},
                  child: const Text(
                    'Map Link',
                    style: TextStyle(
                      color: Color(0xFF8C52FF),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  dateStr,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  timeStr,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Expanded(
                flex: 3,
                child: DropdownButton<String>(
                  value: selectedStatus,
                  dropdownColor: const Color(0xFF2A2A2C),
                  underline: Container(),
                  style: TextStyle(
                    color: getStatusColor(selectedStatus),
                    fontWeight: FontWeight.bold,
                  ),
                  items:
                      <String>[
                        'Pending',
                        'Under Review',
                        'Under Investigation',
                        'Reviewed',
                      ].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      selectedStatus = newValue!;
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
