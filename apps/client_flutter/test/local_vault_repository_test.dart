import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/local_vault_repository.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';

void main() {
  test('loads demo vault with derived metadata', () async {
    final repository = LocalVaultRepository();

    final snapshot = await repository.loadInitialVault();

    expect(snapshot.notes, hasLength(3));
    expect(snapshot.folders, contains('Journal'));
    expect(snapshot.folders, contains('Projects'));

    final roadmap =
        snapshot.notes.firstWhere((note) => note.title == 'Roadmap');
    expect(roadmap.tags, contains('mvp'));
    expect(roadmap.wikilinks, contains('Welcome to Mnemosyne'));

    final welcome = snapshot.notes.firstWhere(
      (note) => note.title == 'Welcome to Mnemosyne',
    );
    expect(welcome.backlinks, contains('Roadmap'));
  });

  test('applyRemoteChanges writes synced markdown into the vault', () async {
    final repository = LocalVaultRepository();
    final root = await Directory.systemTemp.createTemp('mnemosyne_remote_test');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final snapshot = await repository.applyRemoteChanges(
      rootPath: root.path,
      changes: const <RemoteNoteChange>[
        RemoteNoteChange(
          changeId: 'change-1',
          objectId: 'Journal/remote.md',
          operation: 'upsert',
          relativePath: 'Journal/remote.md',
          title: 'Remote Note',
          markdown: '# Remote Note\n\n#synced',
          tags: <String>['synced'],
          wikilinks: <String>[],
        ),
      ],
    );

    expect(snapshot.notes, hasLength(1));
    expect(snapshot.notes.first.title, 'Remote Note');
    expect(snapshot.notes.first.tags, contains('synced'));
  });

  test('loadVaultAtPath keeps an empty vault empty', () async {
    final repository = LocalVaultRepository();
    final root = await Directory.systemTemp.createTemp('mnemosyne_empty_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final snapshot = await repository.loadVaultAtPath(root.path);

    expect(snapshot.rootPath, root.path);
    expect(snapshot.notes, isEmpty);
    expect(snapshot.folders, isEmpty);
  });
}
