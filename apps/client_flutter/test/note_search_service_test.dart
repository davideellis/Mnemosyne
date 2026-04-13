import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/note_search_service.dart';
import 'package:mnemosyne/src/features/notes/vault_models.dart';

void main() {
  const service = NoteSearchService();

  VaultNote note({
    required String title,
    required String relativePath,
    required DateTime modifiedAt,
    String markdown = '',
    List<String> tags = const <String>[],
    List<String> wikilinks = const <String>[],
    List<String> backlinks = const <String>[],
  }) {
    return VaultNote(
      objectId: relativePath,
      title: title,
      relativePath: relativePath,
      modifiedAt: modifiedAt,
      markdown: markdown,
      tags: tags,
      wikilinks: wikilinks,
      backlinks: backlinks,
    );
  }

  test('returns notes in original scoped order when query is empty', () {
    final notes = <VaultNote>[
      note(
        title: 'One',
        relativePath: 'Journal/one.md',
        modifiedAt: DateTime.utc(2026, 4, 1),
      ),
      note(
        title: 'Two',
        relativePath: 'Projects/two.md',
        modifiedAt: DateTime.utc(2026, 4, 2),
      ),
    ];

    final result = service.filterAndRank(
      notes: notes,
      query: '',
      folderFilter: 'Journal',
    );

    expect(result, hasLength(1));
    expect(result.single.title, 'One');
  });

  test('prefers title matches over markdown-only matches', () {
    final notes = <VaultNote>[
      note(
        title: 'Roadmap',
        relativePath: 'Projects/roadmap.md',
        modifiedAt: DateTime.utc(2026, 4, 2),
      ),
      note(
        title: 'Meeting Notes',
        relativePath: 'Journal/meeting.md',
        modifiedAt: DateTime.utc(2026, 4, 3),
        markdown: 'Discuss the roadmap and milestones.',
      ),
    ];

    final result = service.filterAndRank(
      notes: notes,
      query: 'roadmap',
    );

    expect(result, hasLength(2));
    expect(result.first.title, 'Roadmap');
  });

  test('uses recency as a tie breaker for equally ranked matches', () {
    final notes = <VaultNote>[
      note(
        title: 'Sprint Plan',
        relativePath: 'Projects/sprint-plan.md',
        modifiedAt: DateTime.utc(2026, 4, 1),
      ),
      note(
        title: 'Sprint Retro',
        relativePath: 'Projects/sprint-retro.md',
        modifiedAt: DateTime.utc(2026, 4, 5),
      ),
    ];

    final result = service.filterAndRank(
      notes: notes,
      query: 'sprint',
    );

    expect(result, hasLength(2));
    expect(result.first.title, 'Sprint Retro');
  });

  test('tag matches beat markdown-only matches', () {
    final notes = <VaultNote>[
      note(
        title: 'Checklist',
        relativePath: 'Projects/checklist.md',
        modifiedAt: DateTime.utc(2026, 4, 2),
        tags: const <String>['release'],
      ),
      note(
        title: 'Postmortem',
        relativePath: 'Projects/postmortem.md',
        modifiedAt: DateTime.utc(2026, 4, 6),
        markdown: 'release planning follow-up',
      ),
    ];

    final result = service.filterAndRank(
      notes: notes,
      query: 'release',
    );

    expect(result, hasLength(2));
    expect(result.first.title, 'Checklist');
  });

  test('requires all query tokens to match somewhere in the note', () {
    final notes = <VaultNote>[
      note(
        title: 'Release Checklist',
        relativePath: 'Projects/release-checklist.md',
        modifiedAt: DateTime.utc(2026, 4, 2),
        tags: const <String>['release'],
        markdown: 'Checklist for deployment readiness.',
      ),
      note(
        title: 'Release Notes',
        relativePath: 'Projects/release-notes.md',
        modifiedAt: DateTime.utc(2026, 4, 3),
        markdown: 'Summary only.',
      ),
    ];

    final result = service.filterAndRank(
      notes: notes,
      query: 'release checklist',
    );

    expect(result, hasLength(1));
    expect(result.single.title, 'Release Checklist');
  });

  test('exact basename matches outrank partial path matches', () {
    final notes = <VaultNote>[
      note(
        title: 'Meeting',
        relativePath: 'Journal/meeting.md',
        modifiedAt: DateTime.utc(2026, 4, 1),
      ),
      note(
        title: 'Team Sync',
        relativePath: 'Meetings/team-sync.md',
        modifiedAt: DateTime.utc(2026, 4, 5),
      ),
    ];

    final result = service.filterAndRank(
      notes: notes,
      query: 'meeting',
    );

    expect(result, hasLength(2));
    expect(result.first.relativePath, 'Journal/meeting.md');
  });
}
