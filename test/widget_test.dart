import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:samvibhag/core/theme/app_theme.dart';
import 'package:samvibhag/main.dart';

void main() {
  testWidgets('SamVibhag app starts on splash screen', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppThemeController(),
        child: const SamVibhagApp(),
      ),
    );

    expect(find.text('SamVibhag'), findsOneWidget);
    expect(find.text('Fair Expense Sharing'), findsOneWidget);
  });
}
