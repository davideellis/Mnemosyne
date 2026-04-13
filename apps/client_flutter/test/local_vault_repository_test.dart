import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/local_vault_repository.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';

void main() {
  test('loads demo vault with derived metadata', () async {
    final repository = LocalVaultRepository();

    final snapshot = await repository.loadInitialVault();

    expect(snapshot.notes, hasLength(3));
    expect(snapshot.trashedNotes, isEmpty);
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
    expect(welcome.modifiedAt, isA<DateTime>());
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
      changes: const <RemoteSyncChange>[
        RemoteSyncChange(
          changeId: 'change-1',
          objectId: 'Journal/remote.md',
          kind: 'note',
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
    expect(snapshot.trashedNotes, isEmpty);
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
    expect(snapshot.trashedNotes, isEmpty);
    expect(snapshot.folders, isEmpty);
  });

  test('createNote creates a markdown file at the requested relative path',
      () async {
    final repository = LocalVaultRepository();
    final root =
        await Directory.systemTemp.createTemp('mnemosyne_create_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final snapshot = await repository.createNote(
      rootPath: root.path,
      relativePath: 'Journal/new-note',
      title: 'New Note',
    );

    expect(snapshot.notes, hasLength(1));
    expect(snapshot.notes.first.relativePath, 'Journal/new-note.md');
    expect(snapshot.notes.first.markdown, startsWith('# New Note'));
  });

  test('deleteNote removes the selected markdown file', () async {
    final repository = LocalVaultRepository();
    final root =
        await Directory.systemTemp.createTemp('mnemosyne_delete_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final snapshot = await repository.applyRemoteChanges(
      rootPath: root.path,
      changes: const <RemoteSyncChange>[
        RemoteSyncChange(
          changeId: 'change-delete',
          objectId: 'Journal/delete-me.md',
          kind: 'note',
          operation: 'upsert',
          relativePath: 'Journal/delete-me.md',
          title: 'Delete Me',
          markdown: '# Delete Me',
          tags: <String>[],
          wikilinks: <String>[],
        ),
      ],
    );
    final note = snapshot.notes.first;

    final updatedSnapshot = await repository.deleteNote(
      rootPath: snapshot.rootPath,
      note: note,
    );

    expect(updatedSnapshot.notes.length, snapshot.notes.length - 1);
    expect(updatedSnapshot.trashedNotes, hasLength(1));
    expect(
      updatedSnapshot.notes
          .where((candidate) => candidate.objectId == note.objectId),
      isEmpty,
    );
    expect(updatedSnapshot.trashedNotes.first.objectId, note.objectId);
  });

  test('restoreNote moves a trashed note back into the vault', () async {
    final repository = LocalVaultRepository();
    final root =
        await Directory.systemTemp.createTemp('mnemosyne_restore_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final initialSnapshot = await repository.applyRemoteChanges(
      rootPath: root.path,
      changes: const <RemoteSyncChange>[
        RemoteSyncChange(
          changeId: 'change-restore',
          objectId: 'Journal/restore-me.md',
          kind: 'note',
          operation: 'upsert',
          relativePath: 'Journal/restore-me.md',
          title: 'Restore Me',
          markdown: '# Restore Me',
          tags: <String>[],
          wikilinks: <String>[],
        ),
      ],
    );

    final deletedSnapshot = await repository.deleteNote(
      rootPath: root.path,
      note: initialSnapshot.notes.first,
    );

    final restoredSnapshot = await repository.restoreNote(
      rootPath: root.path,
      note: deletedSnapshot.trashedNotes.first,
    );

    expect(restoredSnapshot.notes, hasLength(1));
    expect(restoredSnapshot.trashedNotes, isEmpty);
    expect(restoredSnapshot.notes.first.objectId, 'Journal/restore-me.md');
  });

  test('renameNote moves a note to a new relative path', () async {
    final repository = LocalVaultRepository();
    final root =
        await Directory.systemTemp.createTemp('mnemosyne_rename_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final initialSnapshot = await repository.createNote(
      rootPath: root.path,
      relativePath: 'Journal/original.md',
      title: 'Original',
    );

    final renamedSnapshot = await repository.renameNote(
      rootPath: root.path,
      note: initialSnapshot.notes.first,
      relativePath: 'Projects/renamed.md',
    );

    expect(renamedSnapshot.notes, hasLength(1));
    expect(renamedSnapshot.notes.first.objectId, 'Projects/renamed.md');
    expect(renamedSnapshot.folders, contains('Projects'));
  });

  test('loadVaultAtPath sorts notes by most recent modification first',
      () async {
    final repository = LocalVaultRepository();
    final root =
        await Directory.systemTemp.createTemp('mnemosyne_modified_sort_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final olderFile = File('${root.path}${Platform.pathSeparator}older.md');
    await olderFile.writeAsString('# Older');
    final olderTimestamp = DateTime.utc(2026, 1, 2, 3, 4, 5);
    await olderFile.setLastModified(olderTimestamp);

    final newerFile = File('${root.path}${Platform.pathSeparator}newer.md');
    await newerFile.writeAsString('# Newer');
    final newerTimestamp = DateTime.utc(2026, 1, 3, 3, 4, 5);
    await newerFile.setLastModified(newerTimestamp);

    final snapshot = await repository.loadVaultAtPath(root.path);

    expect(snapshot.notes, hasLength(2));
    expect(snapshot.notes.first.objectId, 'newer.md');
    expect(snapshot.notes.first.modifiedAt, newerTimestamp);
    expect(snapshot.notes.last.objectId, 'older.md');
    expect(snapshot.notes.last.modifiedAt, olderTimestamp);
  });

  test('createNote rejects paths outside the vault or hidden app state',
      () async {
    final repository = LocalVaultRepository();
    final root =
        await Directory.systemTemp.createTemp('mnemosyne_invalid_create_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    await expectLater(
      () => repository.createNote(
        rootPath: root.path,
        relativePath: '../escape.md',
        title: 'Escape',
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('valid vault-relative Markdown path'),
        ),
      ),
    );

    await expectLater(
      () => repository.createNote(
        rootPath: root.path,
        relativePath: '.mnemosyne/internal.md',
        title: 'Hidden',
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('valid vault-relative Markdown path'),
        ),
      ),
    );
  });

  test('renameNote rejects moves into hidden app state', () async {
    final repository = LocalVaultRepository();
    final root =
        await Directory.systemTemp.createTemp('mnemosyne_invalid_rename_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final initialSnapshot = await repository.createNote(
      rootPath: root.path,
      relativePath: 'Journal/original.md',
      title: 'Original',
    );

    await expectLater(
      () => repository.renameNote(
        rootPath: root.path,
        note: initialSnapshot.notes.first,
        relativePath: '.mnemosyne/trash/hidden.md',
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('valid vault-relative Markdown path'),
        ),
      ),
    );
  });

  test('applyRemoteChanges ignores paths targeting hidden app state',
      () async {
    final repository = LocalVaultRepository();
    final root =
        await Directory.systemTemp.createTemp('mnemosyne_hidden_remote_vault');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final snapshot = await repository.applyRemoteChanges(
      rootPath: root.path,
      changes: const <RemoteSyncChange>[
        RemoteSyncChange(
          changeId: 'change-hidden',
          objectId: '.mnemosyne/hidden.md',
          kind: 'note',
          operation: 'upsert',
          relativePath: '.mnemosyne/hidden.md',
          title: 'Hidden',
          markdown: '# Hidden',
          tags: <String>[],
          wikilinks: <String>[],
        ),
      ],
    );

    expect(snapshot.notes, isEmpty);
    final hiddenFile = File(
      '${root.path}${Platform.pathSeparator}.mnemosyne${Platform.pathSeparator}hidden.md',
    );
    expect(await hiddenFile.exists(), isFalse);
  });
}
