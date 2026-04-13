import 'vault_models.dart';

class NoteSearchService {
  const NoteSearchService();

  List<VaultNote> filterAndRank({
    required List<VaultNote> notes,
    required String query,
    String? folderFilter,
  }) {
    final scopedNotes = notes.where((note) {
      if (folderFilter != null && !_noteMatchesFolder(note, folderFilter)) {
        return false;
      }
      return true;
    }).toList(growable: false);

    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return scopedNotes;
    }

    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final rankedNotes = <({VaultNote note, int score})>[];

    for (final note in scopedNotes) {
      final score = _noteSearchScore(note, normalizedQuery, tokens);
      if (score <= 0) {
        continue;
      }
      rankedNotes.add((note: note, score: score));
    }

    rankedNotes.sort((left, right) {
      final scoreComparison = right.score.compareTo(left.score);
      if (scoreComparison != 0) {
        return scoreComparison;
      }

      final modifiedComparison =
          right.note.modifiedAt.compareTo(left.note.modifiedAt);
      if (modifiedComparison != 0) {
        return modifiedComparison;
      }

      return left.note.title.compareTo(right.note.title);
    });

    return rankedNotes.map((entry) => entry.note).toList(growable: false);
  }

  int _noteSearchScore(VaultNote note, String query, List<String> tokens) {
    final title = note.title.toLowerCase();
    final relativePath = note.relativePath.toLowerCase();
    final basename = relativePath.split('/').last.replaceAll('.md', '');
    final markdown = note.markdown.toLowerCase();
    final tags =
        note.tags.map((tag) => tag.toLowerCase()).toList(growable: false);
    final wikilinks = note.wikilinks
        .map((link) => link.toLowerCase())
        .toList(growable: false);
    final backlinks = note.backlinks
        .map((link) => link.toLowerCase())
        .toList(growable: false);

    var score = 0;

    if (title == query) {
      score += 400;
    } else if (title.startsWith(query)) {
      score += 260;
    } else if (title.contains(query)) {
      score += 180;
    }

    if (relativePath == query || basename == query) {
      score += 220;
    } else if (relativePath.contains(query)) {
      score += 120;
    }

    for (final token in tokens) {
      var tokenMatched = false;

      if (title == token) {
        score += 160;
        tokenMatched = true;
      } else if (title.startsWith(token)) {
        score += 110;
        tokenMatched = true;
      } else if (title.contains(token)) {
        score += 70;
        tokenMatched = true;
      }

      if (basename == token) {
        score += 110;
        tokenMatched = true;
      } else if (basename.contains(token)) {
        score += 60;
        tokenMatched = true;
      }

      if (relativePath.contains(token)) {
        score += 45;
        tokenMatched = true;
      }
      if (tags.contains(token)) {
        score += 80;
        tokenMatched = true;
      }
      if (wikilinks.contains(token)) {
        score += 55;
        tokenMatched = true;
      }
      if (backlinks.contains(token)) {
        score += 35;
        tokenMatched = true;
      }
      if (markdown.contains(token)) {
        score += 10;
        tokenMatched = true;
      }

      if (!tokenMatched) {
        return 0;
      }
    }

    return score;
  }

  bool _noteMatchesFolder(VaultNote note, String folder) {
    return note.relativePath == folder ||
        note.relativePath.startsWith('$folder/');
  }
}
