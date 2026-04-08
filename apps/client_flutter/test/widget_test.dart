import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/app.dart';

void main() {
  testWidgets('renders Mnemosyne app shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MnemosyneApp());

    expect(find.byType(MnemosyneApp), findsOneWidget);
    expect(find.byType(WidgetsApp), findsOneWidget);
  });
}
