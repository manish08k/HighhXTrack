import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../data/models/common.dart';
import '../../data/repositories/base.dart';
import '../../data/repositories/document_repo.dart';
import '../../state/providers.dart';

/// A file chosen but not yet saved (owner doesn't exist yet).
class StagedFile {
  StagedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

final attachmentsProvider = FutureProvider.autoDispose.family<List<Attachment>, (String, int)>((ref, key) {
  ref.watchTopics([Chg.todo, Chg.documents]);
  return ref.read(attachmentStoreProvider).list(key.$1, key.$2);
});

Future<List<StagedFile>> pickFiles({bool images = false}) async {
  final files = await FilePicker.pickFiles(type: images ? FileType.image : FileType.any);
  final out = <StagedFile>[];
  for (final f in files) {
    out.add(StagedFile(f.name, await f.readAsBytes()));
  }
  return out;
}

/// Lists, adds, opens and removes attachments for an owner. Before the owner
/// is saved ([ownerId] null) files are staged in memory via [staged].
class AttachmentsSection extends ConsumerWidget {
  const AttachmentsSection({super.key, required this.ownerType, this.ownerId, this.staged = const [], this.onStagedChanged, this.label = 'Attachments'});
  final String ownerType;
  final int? ownerId;
  final List<StagedFile> staged;
  final ValueChanged<List<StagedFile>>? onStagedChanged;
  final String label;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final files = await guard(context, () => pickFiles(), error: 'Could not read the selected file.');
    if (files == null || files.isEmpty) return;
    if (ownerId == null) {
      onStagedChanged?.call([...staged, ...files]);
      return;
    }
    final store = ref.read(attachmentStoreProvider);
    if (!context.mounted) return;
    await guard(context, () async {
      for (final f in files) {
        await store.add(ownerType, ownerId!, f.bytes, f.name);
      }
    }, error: 'Could not save the attachment.');
  }

  Future<void> _open(BuildContext context, Attachment a) async {
    final path = await AttachmentStore.resolve(a);
    if (!await File(path).exists()) {
      if (context.mounted) showSnack(context, 'File is missing');
      return;
    }
    final r = await OpenFilex.open(path);
    if (r.type != ResultType.done && context.mounted) {
      showSnack(context, r.type == ResultType.noAppToOpen ? 'No app found to open this file' : 'Could not open the file');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ownerId == null ? const <Attachment>[] : (ref.watch(attachmentsProvider((ownerType, ownerId!))).value ?? const <Attachment>[]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        for (final a in saved)
          _FileRow(
            name: a.name,
            image: a.isImage,
            size: a.size,
            onOpen: () => _open(context, a),
            onRemove: () async {
              if (await confirmDialog(context, title: 'Remove attachment?', message: a.name, confirm: 'Remove')) {
                await ref.read(attachmentStoreProvider).remove(a);
              }
            },
          ),
        for (var k = 0; k < staged.length; k++)
          _FileRow(name: staged[k].name, image: false, size: staged[k].bytes.length, onRemove: () => onStagedChanged?.call([...staged]..removeAt(k))),
        OutlinedButton.icon(onPressed: () => _add(context, ref), icon: const Icon(Icons.attach_file_rounded), label: const Text('Add file or photo')),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.name, required this.image, required this.size, this.onOpen, required this.onRemove});
  final String name;
  final bool image;
  final int size;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final kb = size / 1024;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Material(
        color: context.colors.surfaceContainerHigh,
        borderRadius: Radii.field,
        child: ListTile(
          shape: const RoundedRectangleBorder(borderRadius: Radii.field),
          leading: Icon(image ? Icons.image_outlined : Icons.insert_drive_file_outlined),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(kb > 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '${kb.toStringAsFixed(0)} KB${onOpen == null ? ' · saved with item' : ''}'),
          onTap: onOpen,
          trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.close_rounded), onPressed: onRemove),
        ),
      ),
    );
  }
}

/// Persists staged files once the owner has an id.
Future<void> saveStaged(WidgetRef ref, String ownerType, int ownerId, List<StagedFile> staged) async {
  final store = ref.read(attachmentStoreProvider);
  for (final f in staged) {
    await store.add(ownerType, ownerId, f.bytes, f.name);
  }
}
