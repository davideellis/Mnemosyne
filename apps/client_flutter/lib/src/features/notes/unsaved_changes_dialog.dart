import 'package:flutter/material.dart';

enum UnsavedChangesAction {
  save,
  discard,
  cancel,
}

class UnsavedChangesDialog extends StatelessWidget {
  const UnsavedChangesDialog({
    super.key,
    required this.targetLabel,
  });

  final String targetLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unsaved changes'),
      content: Text(
        'You have local edits that have not been saved yet. Save them before opening $targetLabel?',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(UnsavedChangesAction.cancel);
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(UnsavedChangesAction.discard);
          },
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(UnsavedChangesAction.save);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
