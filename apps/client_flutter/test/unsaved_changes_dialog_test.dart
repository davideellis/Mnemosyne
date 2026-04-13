import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/unsaved_changes_dialog.dart';

void main() {
  testWidgets('renders save, discard, and cancel options', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnsavedChangesDialog(targetLabel: 'Roadmap'),
        ),
      ),
    );

    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(find.textContaining('before opening Roadmap'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('returns the selected action', (tester) async {
    UnsavedChangesAction? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDialog<UnsavedChangesAction>(
                      context: context,
                      builder: (context) =>
                          const UnsavedChangesDialog(targetLabel: 'Inbox'),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(result, UnsavedChangesAction.discard);
  });
}
