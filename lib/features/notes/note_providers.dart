import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/knowledge.dart';
import '../../data/repositories/base.dart';
import '../../data/repositories/note_repo.dart';
import '../../state/providers.dart';

final notesProvider = FutureProvider.autoDispose.family<List<Note>, NoteQuery>((ref, q) {
  ref.watchTopics([Chg.notes]);
  return ref.read(noteRepoProvider).query(q);
});

final noteFoldersProvider = FutureProvider.autoDispose<List<NoteFolder>>((ref) {
  ref.watchTopics([Chg.notes]);
  return ref.read(noteRepoProvider).folders();
});

final noteTagsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  ref.watchTopics([Chg.notes]);
  return ref.read(noteRepoProvider).tags();
});
