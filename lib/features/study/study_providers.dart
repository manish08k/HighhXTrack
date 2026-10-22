import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dates.dart';
import '../../data/models/knowledge.dart';
import '../../data/repositories/base.dart';
import '../../data/repositories/study_repo.dart';
import '../../state/providers.dart';

final subjectsProvider = FutureProvider.autoDispose<List<Subject>>((ref) {
  ref.watchTopics([Chg.study]);
  return ref.read(studyRepoProvider).subjects();
});

final archivedSubjectsProvider = FutureProvider.autoDispose<List<Subject>>((ref) {
  ref.watchTopics([Chg.study]);
  return ref.read(studyRepoProvider).subjects(archived: true);
});

final subjectProvider = FutureProvider.autoDispose.family<Subject?, int>((ref, id) {
  ref.watchTopics([Chg.study]);
  return ref.read(studyRepoProvider).subject(id);
});

final topicsProvider = FutureProvider.autoDispose.family<List<Topic>, int>((ref, subjectId) {
  ref.watchTopics([Chg.study]);
  return ref.read(studyRepoProvider).topics(subjectId);
});

final sessionsProvider = FutureProvider.autoDispose.family<List<StudySession>, int?>((ref, subjectId) {
  ref.watchTopics([Chg.study]);
  return ref.read(studyRepoProvider).sessions(subjectId: subjectId);
});

class StudySummary {
  const StudySummary({
    required this.todaySec,
    required this.weekSec,
    required this.totalSec,
    required this.streak,
    required this.bestStreak,
    required this.perDay,
    required this.dayTotals,
    required this.topicsDone,
    required this.topicsTotal,
  });
  final int todaySec;
  final int weekSec;
  final int totalSec;
  final int streak;
  final int bestStreak;
  final List<int> perDay;
  final Map<int, int> dayTotals;
  final int topicsDone;
  final int topicsTotal;
}

final studySummaryProvider = FutureProvider.autoDispose<StudySummary>((ref) async {
  ref.watchTopics([Chg.study]);
  final repo = ref.read(studyRepoProvider);
  final now = DateTime.now();
  final totals = await repo.dayTotals();
  final (done, all) = await repo.topicCompletion();
  return StudySummary(
    todaySec: await repo.secondsBetween(D.today(), D.endOfDay(now)),
    weekSec: await repo.secondsBetween(D.startOfWeek(now), D.endOfDay(now)),
    totalSec: await repo.totalSeconds(),
    streak: studyStreak(totals),
    bestStreak: bestStudyStreak(totals),
    perDay: await repo.perDay(14),
    dayTotals: totals,
    topicsDone: done,
    topicsTotal: all,
  );
});

final studyDistributionProvider = FutureProvider.autoDispose<List<(String, int, int)>>((ref) {
  ref.watchTopics([Chg.study]);
  return ref.read(studyRepoProvider).distribution(days: 30);
});
