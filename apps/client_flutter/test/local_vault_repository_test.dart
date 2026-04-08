import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/local_vault_repository.dart';

void main() {
  test('loads demo vault with derived metadata', () async {
    final repository = LocalVaultRepository();

    final snapshot = await repository.loadInitialVault();

    expect(snapshot.notes, hasLength(3));
    expect(snapshot.folders, contains('Journal'));
    expect(snapshot.folders, contains('Projects'));

    final roadmap = snapshot.notes.firstWhere((note) => note.title == 'Roadmap');
    expect(roadmap.tags, contains('mvp'));
    expect(roadmap.wikilinks, contains('Welcome to Mnemosyne'));

    final welcome = snapshot.notes.firstWhere(
      (note) => note.title == 'Welcome to Mnemosyne',
    );
    expect(welcome.backlinks, contains('Roadmap'));
  });
}
