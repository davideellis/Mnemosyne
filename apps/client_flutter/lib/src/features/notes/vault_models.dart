class VaultNote {
  const VaultNote({
    required this.objectId,
    required this.title,
    required this.relativePath,
    required this.markdown,
    required this.tags,
    required this.wikilinks,
    required this.backlinks,
  });

  final String objectId;
  final String title;
  final String relativePath;
  final String markdown;
  final List<String> tags;
  final List<String> wikilinks;
  final List<String> backlinks;

  VaultNote copyWith({
    String? title,
    String? markdown,
    List<String>? tags,
    List<String>? wikilinks,
    List<String>? backlinks,
  }) {
    return VaultNote(
      objectId: objectId,
      title: title ?? this.title,
      relativePath: relativePath,
      markdown: markdown ?? this.markdown,
      tags: tags ?? this.tags,
      wikilinks: wikilinks ?? this.wikilinks,
      backlinks: backlinks ?? this.backlinks,
    );
  }
}

class VaultSnapshot {
  const VaultSnapshot({
    required this.rootPath,
    required this.notes,
    required this.trashedNotes,
    required this.folders,
  });

  final String rootPath;
  final List<VaultNote> notes;
  final List<VaultNote> trashedNotes;
  final List<String> folders;
}
