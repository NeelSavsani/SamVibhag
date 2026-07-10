import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/group_model.dart';
import '../services/pdf_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.group,
  });

  final GroupModel group;

  @override
  State<ReportScreen> createState() =>
      _ReportScreenState();
}

class _ReportScreenState
    extends State<ReportScreen> {

  Uint8List? pdfData;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    generatePdf();
  }

  Future<void> generatePdf() async {

    final data =
        await PdfService
            .generateGroupReport(
      widget.group,
    );

    if (!mounted) return;

    setState(() {
      pdfData = data;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Expense Report',

          style: TextStyle(
            color: Colors.white,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),

      body: isLoading

          ? const Center(
              child:
                  CircularProgressIndicator(),
            )

          : PdfPreview(
              build: (format) async =>
                  pdfData!,
            ),
    );
  }
}