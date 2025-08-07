import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PatientManagementPage extends StatefulWidget {
  const PatientManagementPage({super.key});

  @override
  State<PatientManagementPage> createState() => _PatientManagementPageState();
}

class _PatientManagementPageState extends State<PatientManagementPage> {
  DocumentSnapshot? selectedPatient;

  // Controllers
  final TextEditingController nameController = TextEditingController();
  final TextEditingController genderController = TextEditingController();
  final TextEditingController guardianNameController = TextEditingController();
  final TextEditingController guardianContactController =
      TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController mohAreaController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController wardNoController = TextEditingController();
  final TextEditingController bedNoController = TextEditingController();
  final TextEditingController medicineController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  final TextEditingController schoolWorkController = TextEditingController();

  String? status;
  String? type;

  @override
  void dispose() {
    nameController.dispose();
    genderController.dispose();
    guardianNameController.dispose();
    guardianContactController.dispose();
    phoneController.dispose();
    emailController.dispose();
    mohAreaController.dispose();
    addressController.dispose();
    wardNoController.dispose();
    bedNoController.dispose();
    medicineController.dispose();
    remarkController.dispose();
    schoolWorkController.dispose();
    super.dispose();
  }

  void populateForm(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    nameController.text = data['fullname'] ?? '';
    genderController.text = data['gender'] ?? '';
    guardianNameController.text = data['guardian_name'] ?? '';
    guardianContactController.text = data['guardian_contact'] ?? '';
    phoneController.text = data['phone_number'] ?? '';
    emailController.text = data['email'] ?? '';
    mohAreaController.text = data['moh_area'] ?? '';
    addressController.text = data['address'] ?? '';
    wardNoController.text = data['ward_no'] ?? '';
    bedNoController.text = data['bed_no'] ?? '';
    medicineController.text = data['medicine'] ?? '';
    remarkController.text = data['remark'] ?? '';
    schoolWorkController.text = data['school/work'] ?? '';
    status = data['status'] ?? '';
    type = data['type'] ?? '';

    setState(() {});
  }

  int calculateAge(Timestamp dob) {
    DateTime birthDate = dob.toDate();
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Welcome!",
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                statCard(
                  "Current Number of Cases",
                  "30.7k",
                  'images/graph.png',
                  Colors.purple,
                ),
                statCard(
                  "Total Discharged (Month)",
                  "58",
                  'images/graph.png',
                  Colors.deepPurple,
                ),
                statCard(
                  "Number of Deaths",
                  "125",
                  'images/graph.png',
                  Colors.deepPurple,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 3, child: buildPatientTable()),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: buildPatientForm()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPatientTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Name', style: TextStyle(color: Colors.white70)),
                ),
                Expanded(
                  child: Text(
                    'Gender',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                Expanded(
                  child: Text('Age', style: TextStyle(color: Colors.white70)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Admission Date',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Status',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'MOH Area',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Address',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('dengue_cases')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    int age = calculateAge(doc['date_of_birth']);
                    String admissionDate = DateFormat(
                      'yyyy-MM-dd',
                    ).format(doc['date_of_admission'].toDate());
                    return ListTile(
                      onTap: () {
                        selectedPatient = doc;
                        populateForm(doc);
                      },
                      title: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              doc['fullname'] ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              doc['gender'] ?? '',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '$age',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              admissionDate,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              doc['status'] ?? '',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              doc['moh_area'] ?? '',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              doc['address'] ?? '',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPatientForm() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit Patient Details',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 20),
            buildTextField(nameController, 'Full Name'),
            buildTextField(genderController, 'Gender'),
            buildTextField(guardianNameController, 'Guardian Name'),
            buildTextField(guardianContactController, 'Guardian Contact'),
            buildTextField(phoneController, 'Phone Number'),
            buildTextField(emailController, 'Email'),
            buildTextField(mohAreaController, 'MOH Area'),
            buildTextField(addressController, 'Address'),
            buildTextField(wardNoController, 'Ward No'),
            buildTextField(bedNoController, 'Bed No'),
            buildTextField(medicineController, 'Medicine'),
            buildTextField(schoolWorkController, 'School/Work'),
            buildTextField(remarkController, 'Remarks'),
            buildDropdown('Status', status, [
              'Active',
              'Recovered',
              'Deceased',
            ], (value) => setState(() => status = value)),
            buildDropdown('Type', type, [
              'Admitted',
              'Transferred',
              'Discharged',
            ], (value) => setState(() => type = value)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                if (selectedPatient != null) {
                  FirebaseFirestore.instance
                      .collection('dengue_cases')
                      .doc(selectedPatient!.id)
                      .update({
                        'fullname': nameController.text,
                        'gender': genderController.text,
                        'guardian_name': guardianNameController.text,
                        'guardian_contact': guardianContactController.text,
                        'phone_number': phoneController.text,
                        'email': emailController.text,
                        'moh_area': mohAreaController.text,
                        'address': addressController.text,
                        'ward_no': wardNoController.text,
                        'bed_no': bedNoController.text,
                        'medicine': medicineController.text,
                        'remark': remarkController.text,
                        'school/work': schoolWorkController.text,
                        'status': status,
                        'type': type,
                      });
                }
              },
              child: const Center(
                child: Text(
                  'Save Changes',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.black,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget buildDropdown(
    String label,
    String? value,
    List<String> items,
    void Function(String?) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: value.isEmptyOrNull ? null : value,
        dropdownColor: Colors.black,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.black,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(e, style: const TextStyle(color: Colors.white)),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget statCard(String title, String value, String graphAsset, Color color) {
    return Container(
      width: 300,
      height: 140,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              graphAsset,
              height: 40,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }
}

extension NullableString on String? {
  bool get isEmptyOrNull => this == null || this!.isEmpty;
}
