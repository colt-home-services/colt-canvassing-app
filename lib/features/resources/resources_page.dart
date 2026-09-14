import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/chs_colors.dart';
import 'link_launcher_stub.dart'
    if (dart.library.html) 'link_launcher_web.dart';
import 'resource_service.dart';

class ResourcesPage extends StatefulWidget {
  const ResourcesPage({super.key});

  @override
  State<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends State<ResourcesPage> {
  late final ResourceService _service;

  bool _loading = true;
  bool _isManager = false;
  bool _reordering = false;
  String? _error;
  List<AppResource> _resources = const [];

  @override
  void initState() {
    super.initState();
    _service = ResourceService(Supabase.instance.client);
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final isManager = await _service.isManager();
      final resources = await _service.fetchResources(
        includeInactive: isManager,
      );
      if (!mounted) return;
      setState(() {
        _isManager = isManager;
        _resources = resources;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([AppResource? resource]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ResourceEditorDialog(service: _service, resource: resource),
    );
    if (saved == true) _fetch();
  }

  Future<void> _deleteResource(AppResource resource) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete resource?'),
        content: Text(resource.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteResource(resource.id);
      if (!mounted) return;
      _fetch();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Delete failed: $e');
    }
  }

  Future<void> _copyUrl(AppResource resource) async {
    await Clipboard.setData(ClipboardData(text: resource.url));
    if (!mounted) return;
    _showSnack('Copied ${resource.title}');
  }

  Future<void> _openUrl(AppResource resource) async {
    final opened = await openExternalUrl(resource.url);
    if (opened) return;
    await _copyUrl(resource);
  }

  Future<void> _reorderItem(int oldIndex, int newIndex) async {
    final previous = List<AppResource>.from(_resources);
    final next = List<AppResource>.from(_resources);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);

    setState(() {
      _resources = next;
      _reordering = true;
    });

    try {
      await _service.reorderResources(next);
      if (!mounted) return;
      setState(() => _reordering = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resources = previous;
        _reordering = false;
      });
      _showSnack('Reorder failed: $e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kChsBackground,
      appBar: AppBar(
        title: const Text('Resources'),
        actions: [
          if (_reordering)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _reordering ? null : _fetch,
          ),
        ],
      ),
      floatingActionButton: _isManager
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_link),
              label: const Text('Add resource'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 34),
              const SizedBox(height: 10),
              Text(
                'Could not load resources:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _fetch,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_resources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _isManager
                ? 'No resources yet. Add the first link.'
                : 'No resources have been posted yet.',
            style: const TextStyle(color: kChsTextSecondary),
          ),
        ),
      );
    }

    if (_isManager) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _resources.length,
        onReorderItem: _reordering ? (_, index) {} : _reorderItem,
        proxyDecorator: (child, index, animation) =>
            Material(color: Colors.transparent, elevation: 6, child: child),
        itemBuilder: (context, index) {
          final resource = _resources[index];
          return Padding(
            key: ValueKey(resource.id),
            padding: const EdgeInsets.only(bottom: 10),
            child: _ResourceCard(
              resource: resource,
              isManager: true,
              dragIndex: index,
              onOpen: () => _openUrl(resource),
              onCopy: () => _copyUrl(resource),
              onEdit: () => _openEditor(resource),
              onDelete: () => _deleteResource(resource),
            ),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      itemCount: _resources.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final resource = _resources[index];
        return _ResourceCard(
          resource: resource,
          isManager: false,
          onOpen: () => _openUrl(resource),
          onCopy: () => _copyUrl(resource),
          onEdit: () {},
          onDelete: () {},
        );
      },
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.resource,
    required this.isManager,
    required this.onOpen,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    this.dragIndex,
  });

  final AppResource resource;
  final bool isManager;
  final int? dragIndex;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final inactive = !resource.isActive;
    return Card(
      elevation: 0,
      color: inactive ? Colors.grey.shade100 : kChsCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: inactive ? Colors.grey.shade300 : const Color(0xFFE5E8EE),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isManager && dragIndex != null) ...[
              ReorderableDragStartListener(
                index: dragIndex!,
                child: const SizedBox(
                  width: 28,
                  height: 36,
                  child: Icon(
                    Icons.drag_indicator,
                    color: kChsTextSecondary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: inactive
                    ? Colors.grey.shade300
                    : kChsPrimary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.link,
                color: inactive ? Colors.grey.shade700 : kChsPrimary,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        resource.title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: inactive
                              ? Colors.grey.shade700
                              : kChsTextPrimary,
                        ),
                      ),
                      if (inactive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'Hidden',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (resource.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      resource.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: kChsTextSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        resource.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: inactive ? Colors.grey.shade600 : kChsPrimary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: inactive
                              ? Colors.grey.shade600
                              : kChsPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 2,
              children: [
                _ResourceIconButton(
                  tooltip: 'Open link',
                  icon: Icons.open_in_new,
                  onPressed: onOpen,
                ),
                _ResourceIconButton(
                  tooltip: 'Copy link',
                  icon: Icons.copy,
                  onPressed: onCopy,
                ),
                if (isManager) ...[
                  _ResourceIconButton(
                    tooltip: 'Edit',
                    icon: Icons.edit_outlined,
                    onPressed: onEdit,
                  ),
                  _ResourceIconButton(
                    tooltip: 'Delete',
                    icon: Icons.delete_outline,
                    color: Colors.red.shade700,
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceIconButton extends StatelessWidget {
  const _ResourceIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 18, color: color),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    );
  }
}

class _ResourceEditorDialog extends StatefulWidget {
  const _ResourceEditorDialog({required this.service, this.resource});

  final ResourceService service;
  final AppResource? resource;

  @override
  State<_ResourceEditorDialog> createState() => _ResourceEditorDialogState();
}

class _ResourceEditorDialogState extends State<_ResourceEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _descriptionCtrl;

  bool _isActive = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final resource = widget.resource;
    _titleCtrl = TextEditingController(text: resource?.title ?? '');
    _urlCtrl = TextEditingController(text: resource?.url ?? '');
    _descriptionCtrl = TextEditingController(text: resource?.description ?? '');
    _isActive = resource?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.service.saveResource(
        id: widget.resource?.id,
        title: _titleCtrl.text,
        url: _urlCtrl.text,
        description: _descriptionCtrl.text,
        sortOrder: widget.resource?.sortOrder ?? 0,
        isActive: _isActive,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  String? _validateUrl(String? value) {
    final rawUrl = value?.trim() ?? '';
    final url = ResourceService.normalizeUrl(rawUrl);
    final uri = Uri.tryParse(url);
    if (rawUrl.isEmpty) return 'Enter a URL';
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid URL';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Use http or https';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.resource != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: kChsPrimary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add_link,
                        color: kChsPrimary,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEditing ? 'Edit resource' : 'Add resource',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kChsTextPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _titleCtrl,
                  enabled: !_saving,
                  decoration: _fieldDecoration(
                    label: 'Title',
                    icon: Icons.label_outline,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _urlCtrl,
                  enabled: !_saving,
                  decoration: _fieldDecoration(
                    label: 'URL',
                    hint: 'youtube.com or https://example.com',
                    icon: Icons.link,
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  validator: _validateUrl,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionCtrl,
                  enabled: !_saving,
                  decoration: _fieldDecoration(
                    label: 'Description',
                    icon: Icons.notes_outlined,
                  ),
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                _VisibilityToggle(
                  value: _isActive,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save, size: 18),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDDE1E7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kChsPrimary, width: 1.5),
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? () => onChanged(!value) : null,
      child: Container(
        height: 52,
        padding: const EdgeInsets.only(left: 14, right: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDDE1E7)),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20,
              color: kChsTextSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value ? 'Visible to canvassers' : 'Hidden from canvassers',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kChsTextPrimary,
                ),
              ),
            ),
            Switch(value: value, onChanged: enabled ? onChanged : null),
          ],
        ),
      ),
    );
  }
}
