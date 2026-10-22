import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/planner.dart';
import '../../data/repositories/base.dart';
import '../../state/providers.dart';

final documentsProvider = FutureProvider.autoDispose<List<Doc>>((ref) {
  ref.watchTopics([Chg.documents]);
  return ref.read(documentRepoProvider).all();
});

final documentProvider = FutureProvider.autoDispose.family<Doc?, int>((ref, id) {
  ref.watchTopics([Chg.documents]);
  return ref.read(documentRepoProvider).get(id);
});

IconData docIcon(String category) => switch (category) {
  'Passport' => Icons.travel_explore_rounded,
  'Driving License' => Icons.directions_car_rounded,
  'Vehicle Insurance' => Icons.car_crash_outlined,
  'Health Insurance' => Icons.health_and_safety_outlined,
  'Certificates' => Icons.workspace_premium_outlined,
  'ID documents' => Icons.badge_outlined,
  _ => Icons.description_outlined,
};

String docDaysLabel(Doc d) {
  final n = d.daysLeft;
  if (n == null) return 'No expiry date';
  if (n < 0) return 'Expired ${-n} ${-n == 1 ? 'day' : 'days'} ago';
  if (n == 0) return 'Expires today';
  if (n < 60) return 'Expires in $n ${n == 1 ? 'day' : 'days'}';
  final m = (n / 30.4).floor();
  return m < 24 ? 'Expires in $m months' : 'Expires in ${(n / 365).floor()} years';
}
