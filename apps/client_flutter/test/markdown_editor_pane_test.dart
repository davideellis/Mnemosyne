import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mnemosyne/src/features/notes/markdown_editor_pane.dart';

void main() {
  testWidgets('defaults to preview and keeps edit as the second tab',
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
              onOpenInternalLink: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.byType(Markdown), findsOneWidget);
    expect(find.text('Preview Title'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(Markdown), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    controller.text = '# Updated Title';
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
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
              onOpenInternalLink: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Nothing to preview yet.'), findsOneWidget);
  });

  test('converts wikilinks into internal preview links', () {
    final rendered = MarkdownEditorPane.renderableMarkdownForPreview(
      'See [[Roadmap]] and [[Project Plan|plan]].',
    );

    expect(rendered, contains('[Roadmap](mnemosyne://note/Roadmap)'));
    expect(
      rendered,
      contains('[plan](mnemosyne://note/Project%20Plan)'),
    );
  });
}
