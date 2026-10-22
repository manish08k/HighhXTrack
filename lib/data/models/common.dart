import '../../core/modules.dart';
import '../../core/utils/dates.dart';

bool b(Object? v) => v == 1 || v == true;
int i(bool v) => v ? 1 : 0;

class Attachment {
  const Attachment({this.id, required this.ownerType, required this.ownerId, required this.name, required this.path, this.size = 0, required this.createdAt});

  final int? id;
  final String ownerType;
  final int ownerId;
  final String name;
  final String path;
  final int size;
  final DateTime createdAt;

  bool get isImage {
    final l = name.toLowerCase();
    return l.endsWith('.jpg') || l.endsWith('.jpeg') || l.endsWith('.png') || l.endsWith('.webp') || l.endsWith('.heic');
  }

  factory Attachment.fromMap(Map<String, Object?> m) => Attachment(
    id: m['id'] as int,
    ownerType: m['owner_type'] as String,
    ownerId: m['owner_id'] as int,
    name: m['name'] as String,
    path: m['path'] as String,
    size: m['size'] as int? ?? 0,
    createdAt: D.fromMs(m['created_at'] as int),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'owner_type': ownerType,
    'owner_id': ownerId,
    'name': name,
    'path': path,
    'size': size,
    'created_at': D.ms(createdAt),
  };
}

/// A pointer from one item to an item in another module.
class ItemLink {
  const ItemLink(this.module, this.id);
  final AppModule module;
  final int? id;
}
