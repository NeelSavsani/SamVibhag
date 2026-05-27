import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/group_model.dart';

class PdfService {

  static Future<Uint8List> generateGroupReport(
    GroupModel group,
  ) async {

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,

        build: (context) {

          return [

            pw.Text(
              'SamVibhag Report',

              style: pw.TextStyle(
                fontSize: 28,
                fontWeight:
                    pw.FontWeight.bold,
              ),
            ),

            pw.SizedBox(height: 10),

            pw.Text(
              'Group: ${group.groupName}',

              style: const pw.TextStyle(
                fontSize: 20,
              ),
            ),

            pw.SizedBox(height: 20),

            pw.Text(
              'Members',

              style: pw.TextStyle(
                fontWeight:
                    pw.FontWeight.bold,

                fontSize: 18,
              ),
            ),

            pw.SizedBox(height: 10),

            ...group.members.map(
              (member) =>
                  pw.Bullet(
                text: member,
              ),
            ),

            pw.SizedBox(height: 25),

            pw.Text(
              'Expenses',

              style: pw.TextStyle(
                fontWeight:
                    pw.FontWeight.bold,

                fontSize: 18,
              ),
            ),

            pw.SizedBox(height: 10),

            pw.TableHelper.fromTextArray(
              headers: [
                'Title',
                'Category',
                'Paid By',
                'Amount',
                'Date',
              ],

              data: group.expenses.map(
                (expense) {

                  return [

                    expense.title,

                    expense.category,

                    expense.paidBy,

                    'Rs. ${expense.amount.toStringAsFixed(0)}',

                    DateFormat(
                      'dd/MM/yyyy',
                    ).format(
                      expense.date,
                    ),
                  ];
                },
              ).toList(),
            ),

            pw.SizedBox(height: 25),

            pw.Text(
              'Settlements',

              style: pw.TextStyle(
                fontWeight:
                    pw.FontWeight.bold,

                fontSize: 18,
              ),
            ),

            pw.SizedBox(height: 10),

            ...group.settlements.map(
              (settlement) {

                return pw.Padding(
                  padding:
                      const pw.EdgeInsets.only(
                    bottom: 8,
                  ),

                  child: pw.Text(
                    '${settlement.from} pays ${settlement.to} → Rs. ${settlement.amount.toStringAsFixed(0)}',
                  ),
                );
              },
            ),

            pw.SizedBox(height: 30),

            pw.Text(
              'Total Expense: Rs. ${group.totalExpense.toStringAsFixed(0)}',

              style: pw.TextStyle(
                fontWeight:
                    pw.FontWeight.bold,

                fontSize: 20,
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}