import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/markdown_editor_pane.dart';

void main() {
  testWidgets('switches between edit and preview with live markdown text',
      (tester) async {
    final controller = TextEditingController(text: '# Preview Title');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: MarkdownEditorPane(
              controller: controller,
              isReadOnly: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Preview Title'), findsOneWidget);

    controller.text = '# Updated Title';
    await tester.pumpAndSettle();

    expect(find.text('Updated Title'), findsOneWidget);
  });

  testWidgets('shows placeholder markdown when the editor is empty',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: MarkdownEditorPane(
              controller: controller,
              isReadOnly: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to preview yet.'), findsOneWidget);
  });
}
