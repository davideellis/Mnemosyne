import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'sync_models.dart';
import 'vault_models.dart';

class LocalVaultRepository {
  Future<VaultSnapshot> loadInitialVault() async {
    final root =
        Directory(path.join(Directory.systemTemp.path, 'MnemosyneDemoVault'));
    await _seedDemoVault(root);
    return _loadVault(root);
  }

  Future<VaultSnapshot> loadVaultAtPath(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return _loadVault(root);
  }

  Future<VaultSnapshot> saveNote({
    required String rootPath,
    required VaultNote note,
    required String markdown,
  }) async {
    final file = File(path.join(rootPath, note.relativePath));
    await file.create(recursive: true);
    await file.writeAsString(markdown);
    return _loadVault(Directory(rootPath));
  }

  Future<VaultSnapshot> applyRemoteChanges({
    required String rootPath,
    required List<RemoteNoteChange> changes,
  }) async {
    final root = Directory(rootPath);

    for (final change in changes) {
      if (change.relativePath.isEmpty) {
        continue;
      }

      final notePath = _resolveVaultPath(root.path, change.relativePath);
      if (notePath == null) {
        continue;
      }

      final file = File(notePath);
      switch (change.operation) {
        case 'trash':
          if (await file.exists()) {
            await file.delete();
          }
          break;
        case 'upsert':
        case 'restore':
        default:
          await file.create(recursive: true);
          await file.writeAsString(change.markdown);
          break;
      }
    }

    return _loadVault(root);
  }

  Stream<VaultSnapshot> watchVault(String rootPath) async* {
    final root = Directory(rootPath);
    yield await _loadVault(root);

    await for (final _ in root.watch(recursive: true)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      yield await _loadVault(root);
    }
  }

  Future<VaultSnapshot> _loadVault(Directory root) async {
    final files = await root
        .list(recursive: true)
        .where((entity) =>
            entity is File && entity.path.toLowerCase().endsWith('.md'))
        .cast<File>()
        .toList();

    files.sort((left, right) => left.path.compareTo(right.path));

    final folderSet = <String>{};
    final draftNotes = <_DraftNote>[];

    for (final file in files) {
      final relativePath = path.relative(file.path, from: root.path);
      final markdown = await file.readAsString();
      final title = _deriveTitle(relativePath, markdown);
      final tags = _extractTags(markdown);
      final wikilinks = _extractWikilinks(markdown);
      final parentPath = path.dirname(relativePath);
      if (parentPath != '.') {
        _collectFolders(folderSet, parentPath);
      }

      draftNotes.add(
        _DraftNote(
          objectId: relativePath,
          title: title,
          relativePath: relativePath,
          markdown: markdown,
          tags: tags,
          wikilinks: wikilinks,
        ),
      );
    }

    final aliases = <String, String>{};
    for (final note in draftNotes) {
      aliases[_normalize(note.title)] = note.objectId;
      aliases[_normalize(path.basenameWithoutExtension(note.relativePath))] =
          note.objectId;
      aliases[_normalize(note.relativePath)] = note.objectId;
    }

    final backlinksById = <String, List<String>>{};
    for (final note in draftNotes) {
      for (final link in note.wikilinks) {
        final targetId = aliases[_normalize(link)];
        if (targetId == null || targetId == note.objectId) {
          continue;
        }
        backlinksById.putIfAbsent(targetId, () => <String>[]).add(note.title);
      }
    }

    final notes = draftNotes
        .map(
          (note) => VaultNote(
            objectId: note.objectId,
            title: note.title,
            relativePath: note.relativePath,
            markdown: note.markdown,
            tags: note.tags,
            wikilinks: note.wikilinks,
            backlinks: List<String>.unmodifiable(
                backlinksById[note.objectId] ?? const []),
          ),
        )
        .toList(growable: false);

    final folders = folderSet.toList()..sort();

    return VaultSnapshot(
      rootPath: root.path,
      notes: notes,
      folders: folders,
    );
  }

  Future<void> _seedDemoVault(Directory root) async {
    if (await root.exists()) {
      return;
    }

    final files = <String, String>{
      path.join('Journal', 'welcome.md'): '''
# Welcome to Mnemosyne

Mnemosyne keeps your notes as local Markdown files and syncs them across your devices.

See also [[Roadmap]] and [[Recovery Key]].

#welcome #journal
''',
      path.join('Projects', 'roadmap.md'): '''
# Roadmap

The first milestone focuses on single-user sync, local search, wikilinks, backlinks, and graph view.

Read [[Welcome to Mnemosyne]] for the product framing.

#project #mvp
''',
      path.join('Journal', 'recovery-key.md'): '''
# Recovery Key

Your recovery key is required because operators cannot decrypt your notes.

Reference [[Roadmap]] when documenting setup.

#security #account
''',
    };

    for (final entry in files.entries) {
      final file = File(path.join(root.path, entry.key));
      await file.create(recursive: true);
      await file.writeAsString(entry.value.trimLeft());
    }
  }

  static void _collectFolders(Set<String> folders, String relativeFolder) {
    final parts = path.split(relativeFolder);
    for (var index = 0; index < parts.length; index++) {
      folders.add(path.joinAll(parts.take(index + 1)));
    }
  }

  static String _deriveTitle(String relativePath, String markdown) {
    for (final line in markdown.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        return trimmed.substring(2).trim();
      }
    }
    return path.basenameWithoutExtension(relativePath);
  }

  static List<String> _extractTags(String markdown) {
    final matches = RegExp(r'(^|\s)#([A-Za-z0-9_-]+)', multiLine: true)
        .allMatches(markdown);
    final tags = <String>{};
    for (final match in matches) {
      final value = match.group(2);
      if (value != null && value.isNotEmpty) {
        tags.add(value);
      }
    }
    return tags.toList()..sort();
  }

  static List<String> _extractWikilinks(String markdown) {
    final matches = RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]')
        .allMatches(markdown);
    final links = <String>[];
    for (final match in matches) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        links.add(value);
      }
    }
    return links;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll('\\', '/');
  }

  static String? _resolveVaultPath(String rootPath, String relativePath) {
    final normalized = path.normalize(relativePath);
    if (path.isAbsolute(normalized) || normalized.startsWith('..')) {
      return null;
    }
    return path.join(rootPath, normalized);
  }
}

class _DraftNote {
  const _DraftNote({
    required this.objectId,
    required this.title,
    required this.relativePath,
    required this.markdown,
    required this.tags,
    required this.wikilinks,
  });

  final String objectId;
  final String title;
  final String relativePath;
  final String markdown;
  final List<String> tags;
  final List<String> wikilinks;
}
