import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'PatientManagement.dart';
import 'package:intl/intl.dart';

class PatientFormPage extends StatefulWidget {
  const PatientFormPage({super.key});

  @override
  State<PatientFormPage> createState() => _PatientFormPageState();
}

class _PatientFormPageState extends State<PatientFormPage> {
  final _formKey = GlobalKey<FormState>();
  String? type;
  String? gender;
  bool isPregnant = false;

  DateTime? dateOfAdmit;
  DateTime? dateOfBirth;
  DateTime? dueDate;

  final fullNameController = TextEditingController();
  final remarksController = TextEditingController();
  final medicineController = TextEditingController();
  final emailController = TextEditingController();
  final guardianNameController = TextEditingController();
  final guardianContactController = TextEditingController();
  final phoneController = TextEditingController();
  final hospitalIdController = TextEditingController();
  final wardNoController = TextEditingController();
  final bedNoController = TextEditingController();
  final homeAddressController = TextEditingController();
  final workAddressController = TextEditingController();
  final weeksPregnantController = TextEditingController();

  final mohAreas = [
    "Borella",
    "Colombo Central",
    "Colombo North",
    "Colombo South",
    "Dehiwala",
    "Homagama",
    "Kaduwela",
    "Kesbewa",
    "Kolonnawa",
    "Maharagama",
    "Moratuwa",
    "Nugegoda",
    "Ratmalana",
    "Thimbirigasyaya",
  ];
  String? selectedMohArea;

  Future<void> _pickDate(
    BuildContext context,
    ValueChanged<DateTime?> onPicked,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2025, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  Widget _buildTextField(
    String hint, {
    TextEditingController? controller,
    TextInputType? type,
    int maxLines = 1,
    bool isRequired = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        filled: false,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      validator: isRequired
          ? (val) => val == null || val.isEmpty ? 'Required' : null
          : null,
    );
  }

  Widget _buildDateField(
    String label,
    DateTime? value,
    void Function(DateTime?) onPicked, {
    bool isRequired = false,
  }) {
    return InkWell(
      onTap: () => _pickDate(context, onPicked),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          value != null
              ? DateFormat('dd/MM/yyyy').format(value)
              : 'Select date',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget radioOption(String value, String label, String group) {
    return Row(
      children: [
        Radio<String>(
          value: value,
          groupValue: group == "gender" ? gender : type,
          onChanged: (val) => setState(() {
            if (group == "gender") {
              gender = val!;
            } else {
              type = val!;
            }
          }),
        ),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  Widget navItem(
    String assetPath,
    String label, {
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: selected ? Colors.black : Colors.transparent,
            borderRadius: selected
                ? BorderRadius.zero
                : const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 16 : 20,
            vertical: selected ? 10 : 12,
          ),
          child: Row(
            children: [
              Image.asset(
                assetPath,
                width: 24,
                height: 24,
                color: selected ? Colors.white : Colors.white.withOpacity(0.6),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFFD9B4FF) : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate() && type != null && gender != null) {
      await FirebaseFirestore.instance.collection('dengue_cases').add({
        'fullname': fullNameController.text,
        'hospital_id': hospitalIdController.text,
        'ward_no': wardNoController.text,
        'bed_no': bedNoController.text,
        'phone_number': phoneController.text,
        'moh_area': selectedMohArea,
        'type': type,
        'gender': gender,
        'status': 'Active',
        'date_of_admission': Timestamp.now(),
        'date_of_birth': Timestamp.now(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient info updated successfully!')),
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PatientManagementPage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          Container(
            width: 250,
            color: const Color(0xFF1C1C1E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Image.asset('images/logo.png', width: 50, height: 50),
                      const SizedBox(width: 8),
                      const Text(
                        'Hospital',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                navItem(
                  'images/patient_form_icon.png',
                  'Patient Form',
                  selected: true,
                ),
                navItem('images/map_icon.png', 'Map'),
                navItem(
                  'images/patient_management_icon.png',
                  'Patient management',
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation1, animation2) =>
                            const PatientManagementPage(),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  },
                ),
                navItem('images/analytics_icon.png', 'Analytics'),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 30),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Welcome!",
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Patient Form",
                        style: TextStyle(
                          color: Color(0xFFD9B4FF),
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        "Full Name",
                        controller: fullNameController,
                        isRequired: true,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: selectedMohArea,
                        items: mohAreas
                            .map(
                              (area) => DropdownMenuItem(
                                value: area,
                                child: Text(area),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => selectedMohArea = val),
                        decoration: InputDecoration(
                          hintText: "MOH Area",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (val) => val == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      const Text("TYPE", style: TextStyle(color: Colors.white)),
                      Row(
                        children: [
                          radioOption("New", "New", "type"),
                          radioOption("Transferred", "Transferred", "type"),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildTextField(
                              "Hospital ID",
                              controller: hospitalIdController,
                              isRequired: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              "Ward No.",
                              controller: wardNoController,
                              isRequired: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildTextField(
                              "Bed No.",
                              controller: bedNoController,
                              isRequired: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildDateField(
                        "Date of Admit",
                        dateOfAdmit,
                        (val) => setState(() => dateOfAdmit = val),
                        isRequired: true,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "GENDER",
                        style: TextStyle(color: Colors.white),
                      ),
                      Row(
                        children: [
                          radioOption("Male", "Male", "gender"),
                          radioOption("Female", "Female", "gender"),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildDateField(
                        "Date of Birth",
                        dateOfBirth,
                        (val) => setState(() => dateOfBirth = val),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Checkbox(
                            value: isPregnant,
                            onChanged: (val) =>
                                setState(() => isPregnant = val!),
                          ),
                          const Text(
                            "Pregnant",
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      if (isPregnant) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                "Weeks Pregnant",
                                controller: weeksPregnantController,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDateField(
                                "Due Date",
                                dueDate,
                                (val) => setState(() => dueDate = val),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      _buildTextField(
                        "Home Address",
                        controller: homeAddressController,
                        isRequired: true,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        "School/Work Address",
                        controller: workAddressController,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        "Phone Number",
                        controller: phoneController,
                        isRequired: true,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        "Email",
                        controller: emailController,
                        isRequired: true,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        "Guardian Name",
                        controller: guardianNameController,
                        isRequired: true,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        "Guardian Contact No.",
                        controller: guardianContactController,
                        isRequired: true,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        "Remarks",
                        controller: remarksController,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        "Prescribed Medicine",
                        controller: medicineController,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF9A6AFF),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _submitForm,
                          child: const Text(
                            "SUBMIT",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
