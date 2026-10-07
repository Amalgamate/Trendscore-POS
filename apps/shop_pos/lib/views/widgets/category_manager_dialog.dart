import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../pos_state.dart';
import '../../theme/tokens.dart';

/// Opens the category manager: add, rename, recolour, re-icon and delete
/// categories. Products follow renames; deleting a category that is in use
/// asks where to move its products.
Future<void> showCategoryManager(BuildContext context, PosState state) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CategoryManagerDialog(state: state),
  );
}

class _CategoryManagerDialog extends StatefulWidget {
  const _CategoryManagerDialog({required this.state});
  final PosState state;

  @override
  State<_CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<_CategoryManagerDialog> {
  final _nameCtrl = TextEditingController();
  PosCategory? _editing; // null = adding a new category
  int _color = kCategoryColors.first;
  String _icon = 'box';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _color = kCategoryColors[widget.state.categories.length % kCategoryColors.length];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _startEdit(PosCategory c) {
    setState(() {
      _editing = c;
      _nameCtrl.text = c.name;
      _color = c.colorValue;
      _icon = c.iconKey;
      _error = null;
    });
  }

  void _resetForm() {
    _editing = null;
    _nameCtrl.clear();
    _icon = 'box';
    _color = kCategoryColors[widget.state.categories.length % kCategoryColors.length];
    _error = null;
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (_editing == null) {
        await widget.state.addCategory(_nameCtrl.text, colorValue: _color, iconKey: _icon);
      } else {
        await widget.state.updateCategory(
          _editing!.id,
          name: _nameCtrl.text,
          colorValue: _color,
          iconKey: _icon,
        );
      }
      if (mounted) setState(_resetForm);
    } on PosException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the category: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PosCategory c) async {
    final state = widget.state;
    final count = state.productCountIn(c.name);
    final others = state.categories.where((x) => x.id != c.id).toList();
    if (others.isEmpty) {
      setState(() => _error = 'Keep at least one category.');
      return;
    }

    String target = others.any((o) => o.name == 'Other') ? 'Other' : others.first.name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Delete "${c.name}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (count == 0)
                const Text('No products use this category.')
              else ...[
                Text('$count ${count == 1 ? 'product uses' : 'products use'} this category. '
                    'Move ${count == 1 ? 'it' : 'them'} to:'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(target),
                  initialValue: target,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: others
                      .map((o) => DropdownMenuItem(value: o.name, child: Text(o.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => target = v);
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.status_danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(count == 0 ? 'Delete' : 'Move & delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await state.deleteCategory(c.id, moveProductsTo: count > 0 ? target : null);
      if (mounted && _editing?.id == c.id) setState(_resetForm);
    } on PosException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(560, screen.width - 32),
          maxHeight: screen.height * 0.88,
        ),
        child: ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) {
            final cats = widget.state.categories;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Product Categories',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        color: AppColors.text_tertiary,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // List
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: cats.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 24, endIndent: 24),
                    itemBuilder: (context, i) {
                      final c = cats[i];
                      final count = widget.state.productCountIn(c.name);
                      final isEditing = _editing?.id == c.id;
                      return Container(
                        color: isEditing ? AppColors.accent_light : null,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.color,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border_subtle),
                              ),
                              child: Icon(c.icon, size: 19, color: AppColors.text_secondary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  Text('$count ${count == 1 ? 'item' : 'items'}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: AppColors.text_secondary,
                              onPressed: () => _startEdit(c),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: AppColors.status_danger,
                              onPressed: () => _delete(c),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),

                // Add / edit form
                Container(
                  color: AppColors.bg_canvas,
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _editing == null ? 'ADD A CATEGORY' : 'EDITING "${_editing!.name}"',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.text_tertiary),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameCtrl,
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Category name',
                          hintText: 'e.g. Frozen foods',
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: kCategoryIcons.entries.map((e) {
                          final sel = _icon == e.key;
                          return InkWell(
                            onTap: () => setState(() => _icon = e.key),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: sel ? AppColors.accent_light : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: sel ? AppColors.accent_primary : AppColors.border_subtle,
                                  width: sel ? 2 : 1,
                                ),
                              ),
                              child: Icon(e.value,
                                  size: 18,
                                  color: sel ? AppColors.accent_primary : AppColors.text_secondary),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kCategoryColors.map((value) {
                          final sel = _color == value;
                          return InkWell(
                            onTap: () => setState(() => _color = value),
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: Color(value),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: sel ? AppColors.accent_primary : AppColors.border_strong,
                                  width: sel ? 2.5 : 1,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: AppColors.status_danger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(fontSize: 12, color: AppColors.status_danger)),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_editing != null)
                            TextButton(
                              onPressed: _busy ? null : () => setState(_resetForm),
                              child: const Text('Cancel edit'),
                            ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: Icon(_editing == null ? Icons.add : Icons.check, size: 18),
                            label: Text(_editing == null ? 'Add category' : 'Save changes'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent_primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _busy ? null : _submit,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
