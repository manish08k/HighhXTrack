import 'dart:convert';
import 'dart:ui';

import '../../core/utils/dates.dart';
import 'common.dart';

// ---------------------------------------------------------------- Notes

class NoteFolder {
  const NoteFolder({this.id, required this.name, this.position = 0, this.count = 0});
  final int? id;
  final String name;
  final int position;
  final int count;

  factory NoteFolder.fromMap(Map<String, Object?> m) =>
      NoteFolder(id: m['id'] as int, name: m['name'] as String, position: m['position'] as int? ?? 0, count: m['cnt'] as int? ?? 0);
}

class ChecklistItem {
  ChecklistItem(this.text, {this.done = false});
  String text;
  bool done;

  Map<String, Object> toJson() => {'t': text, 'd': done};
  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(j['t'] as String? ?? '', done: j['d'] == true);
}

class Note {
  const Note({
    this.id,
    this.title = '',
    this.body = '',
    this.checklist = const [],
    this.folderId,
    this.tags = const [],
    this.pinned = false,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });
  final int? id;
  final String title;
  final String body;
  final List<ChecklistItem> checklist;
  final int? folderId;
  final List<String> tags;
  final bool pinned;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty && checklist.every((c) => c.text.trim().isEmpty);

  String get preview {
    if (body.trim().isNotEmpty) return body.replaceAll(RegExp(r'[*_#>`]'), '').trim();
    return checklist.map((c) => '${c.done ? '☑' : '☐'} ${c.text}').join('\n');
  }

  static List<ChecklistItem> decodeChecklist(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      return (jsonDecode(s) as List).map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  factory Note.fromMap(Map<String, Object?> m) => Note(
    id: m['id'] as int,
    title: m['title'] as String? ?? '',
    body: m['body'] as String? ?? '',
    checklist: decodeChecklist(m['checklist'] as String?),
    folderId: m['folder_id'] as int?,
    tags: (m['tags'] as String? ?? '').split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
    pinned: b(m['pinned']),
    archived: b(m['archived']),
    createdAt: D.fromMs(m['created_at'] as int),
    updatedAt: D.fromMs(m['updated_at'] as int),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'body': body,
    'checklist': checklist.isEmpty ? '' : jsonEncode(checklist.map((c) => c.toJson()).toList()),
    'folder_id': folderId,
    'tags': tags.join(','),
    'pinned': i(pinned),
    'archived': i(archived),
    'created_at': D.ms(createdAt),
    'updated_at': D.ms(updatedAt),
  };
}

// ---------------------------------------------------------------- Study

class Subject {
  const Subject({
    this.id,
    required this.name,
    required this.color,
    this.archived = false,
    this.position = 0,
    required this.createdAt,
    this.topicCount = 0,
    this.topicsDone = 0,
    this.totalSeconds = 0,
  });
  final int? id;
  final String name;
  final int color;
  final bool archived;
  final int position;
  final DateTime createdAt;
  final int topicCount;
  final int topicsDone;
  final int totalSeconds;

  Color get colorValue => Color(color);
  double get progress => topicCount == 0 ? 0 : topicsDone / topicCount;

  factory Subject.fromMap(Map<String, Object?> m) => Subject(
    id: m['id'] as int,
    name: m['name'] as String,
    color: m['color'] as int,
    archived: b(m['archived']),
    position: m['position'] as int? ?? 0,
    createdAt: D.fromMs(m['created_at'] as int),
    topicCount: m['topic_count'] as int? ?? 0,
    topicsDone: m['topics_done'] as int? ?? 0,
    totalSeconds: m['total_sec'] as int? ?? 0,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'color': color,
    'archived': i(archived),
    'position': position,
    'created_at': D.ms(createdAt),
  };
}

class Topic {
  const Topic({this.id, required this.subjectId, required this.name, this.notes = '', this.done = false, this.doneAt, this.position = 0, this.seconds = 0});
  final int? id;
  final int subjectId;
  final String name;
  final String notes;
  final bool done;
  final DateTime? doneAt;
  final int position;
  final int seconds;

  factory Topic.fromMap(Map<String, Object?> m) => Topic(
    id: m['id'] as int,
    subjectId: m['subject_id'] as int,
    name: m['name'] as String,
    notes: m['notes'] as String? ?? '',
    done: b(m['done']),
    doneAt: D.fromMsN(m['done_at'] as int?),
    position: m['position'] as int? ?? 0,
    seconds: m['sec'] as int? ?? 0,
  );
}

class StudySession {
  const StudySession({
    this.id,
    this.subjectId,
    this.topicId,
    required this.startedAt,
    required this.durationSec,
    this.kind = 'timer',
    this.notes = '',
    this.subjectName,
    this.topicName,
    this.subjectColor,
  });
  final int? id;
  final int? subjectId;
  final int? topicId;
  final DateTime startedAt;
  final int durationSec;
  final String kind;
  final String notes;
  final String? subjectName;
  final String? topicName;
  final int? subjectColor;

  Duration get duration => Duration(seconds: durationSec);

  factory StudySession.fromMap(Map<String, Object?> m) => StudySession(
    id: m['id'] as int,
    subjectId: m['subject_id'] as int?,
    topicId: m['topic_id'] as int?,
    startedAt: D.fromMs(m['started_at'] as int),
    durationSec: m['duration_sec'] as int,
    kind: m['kind'] as String? ?? 'timer',
    notes: m['notes'] as String? ?? '',
    subjectName: m['subject_name'] as String?,
    topicName: m['topic_name'] as String?,
    subjectColor: m['subject_color'] as int?,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'subject_id': subjectId,
    'topic_id': topicId,
    'started_at': D.ms(startedAt),
    'duration_sec': durationSec,
    'kind': kind,
    'notes': notes,
  };
}
