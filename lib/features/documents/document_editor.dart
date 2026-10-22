import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/planner.dart';
import '../../state/providers.dart';
import '../shared/attachments_section.dart';

const kDocRemindOptions = [7, 15, 30, 60, 90];

class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({super.key, this.id});
  final int? id;
  @override
  ConsumerState<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  Doc? _original;
  bool _loading = true;
  bool _saving = false;
  String _category = kDocCategories.first;
  DateTime? _issue;
  DateTime? _expiry;
  int _remindDays = 30;
  List<StagedFile> _staged = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.id != null) {
      final d = await ref.read(documentRepoProvider).get(widget.id!);
      if (!mounted) return;
      if (d != null) {
        _original = d;
        _name.text = d.name;
        _number.text = d.number;
        _notes.text = d.notes;
        _category = d.category;
        _issue = d.issueAt;
        _expiry = d.expiryAt;
        _remindDays = d.remindDays;
      }
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_issue != null && _expiry != null && _expiry!.isBefore(_issue!)) {
      showSnack(context, 'Expiry date must be after the issue date');
      return;
    }
    setState(() => _saving = true);
    final o = _original;
    final d = Doc(
      id: o?.id,
      name: _name.text.trim(),
      category: _category,
      number: _number.text.trim(),
      issueAt: _issue,
      expiryAt: _expiry,
      notes: _notes.text.trim(),
      remindDays: _remindDays,
      createdAt: o?.createdAt ?? DateTime.now(),
    );
    final ok = await guard(context, () async {
      final id = await ref.read(documentRepoProvider).save(d);
      if (_staged.isNotEmpty) await saveStaged(ref, 'document', id, _staged);
      return id;
    }, error: 'Could not save the document.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    final o = _original;
    return Scaffold(
      appBar: AppBar(title: Text(o == null ? 'New document' : 'Edit document')),
      bottomNavigationBar: FormActionBar(label: o == null ? 'Add document' : 'Save changes', onPressed: _save, busy: _saving),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
          children: [
            AppTextField(
              controller: _name,
              label: 'Name',
              hint: 'e.g. Indian Passport',
              autofocus: o == null,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const FieldLabel('Category'),
            ChoiceChips<String>(options: kDocCategories, selected: _category, wrap: true, label: (c) => c, onSelected: (c) => setState(() => _category = c)),
            AppTextField(controller: _number, label: 'Document number', hint: 'Optional', capitalization: TextCapitalization.characters),
            const FieldLabel('Dates'),
            PickerTile(
              icon: Icons.event_available_outlined,
              label: 'Issue date',
              value: _issue == null ? null : 'Issued ${D.dayMonthYear(_issue!)}',
              onTap: () async {
                final d = await pickDate(context, initial: _issue, last: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _issue = d);
              },
              onClear: () => setState(() => _issue = null),
            ),
            const SizedBox(height: Gap.sm),
            PickerTile(
              icon: Icons.event_busy_outlined,
              label: 'Expiry date',
              value: _expiry == null ? null : 'Expires ${D.dayMonthYear(_expiry!)}',
              onTap: () async {
                final d = await pickDate(context, initial: _expiry ?? D.addMonths(DateTime.now(), 12));
                if (d != null) setState(() => _expiry = d);
              },
              onClear: () => setState(() => _expiry = null),
            ),
            if (_expiry != null) ...[
              const FieldLabel('Renewal reminder'),
              ChoiceChips<int>(
                options: kDocRemindOptions,
                selected: _remindDays,
                wrap: true,
                label: (d) => '$d days before',
                onSelected: (d) => setState(() => _remindDays = d),
              ),
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm, left: Gap.xs),
                child: Text('You will also be notified on the expiry date.', style: context.text.bodySmall),
              ),
            ],
            AppTextField(controller: _notes, label: 'Notes', hint: 'Renewal steps, office address…', maxLines: 5, minLines: 2),
            AttachmentsSection(
              ownerType: 'document',
              ownerId: o?.id,
              staged: _staged,
              onStagedChanged: (s) => setState(() => _staged = s),
              label: 'Scans & photos',
            ),
          ],
        ),
      ),
    );
  }
}
