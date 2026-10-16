import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/member_provider.dart';
import '../../providers/organization_provider.dart';
import '../../providers/todo_provider.dart';
import '../../widgets/account_switcher.dart';
import '../../widgets/common.dart';

/// Un fichier choisi par l'utilisateur.
class PickedImportFile {
  final String name;
  final Uint8List bytes;
  const PickedImportFile(this.name, this.bytes);
}

typedef ImportFilePicker = Future<PickedImportFile?> Function();

const _maxBytes = 5 * 1024 * 1024;

/// Le sélecteur du système (Android) ou du navigateur (PWA).
Future<PickedImportFile?> pickImportFile() async {
  final result = await FilePicker.pickFiles(type: FileType.any, withData: true);
  final file = result?.files.single;
  if (file == null) return null;
  final bytes = file.bytes;
  if (bytes == null) throw Exception('Fichier illisible : choisissez-le à nouveau.');
  return PickedImportFile(file.name, bytes);
}

/// Les imports Excel : télécharger ou partager le modèle de l'église, puis
/// importer le fichier rempli. Tout ou rien : à la moindre erreur, rien
/// n'est importé et chaque ligne fautive est nommée.
class ImportScreen extends StatefulWidget {
  final ImportFilePicker pickFile;
  const ImportScreen({super.key, this.pickFile = pickImportFile});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<Map<String, dynamic>> _kinds = [];
  bool _loading = true;
  String? _error;
  String? _busyKind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final kinds = await context.read<AuthProvider>().api.getImportKinds();
      if (mounted) setState(() => _kinds = kinds);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _busy(String kind, Future<void> Function() action) async {
    if (_busyKind != null) return;
    setState(() => _busyKind = kind);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    } finally {
      if (mounted) setState(() => _busyKind = null);
    }
  }

  Future<void> _download(Map<String, dynamic> kind) => _busy(kind['kind'], () async {
        final auth = context.read<AuthProvider>();
        final template = await auth.api.getImportTemplate(kind['kind']);
        final path = '${template['download_path'] ?? ''}';
        // Sur le web l'adresse est celle de la page ; sur le téléphone, celle du serveur.
        final url = kIsWeb || auth.serverUrl.isEmpty ? Uri.base.resolve(path) : Uri.parse('${auth.serverUrl}$path');
        final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (!opened && mounted) showErrorSnackbar(context, 'Impossible d\'ouvrir le navigateur.');
      });

  Future<void> _share(Map<String, dynamic> kind) => _busy(kind['kind'], () async {
        final template = await context.read<AuthProvider>().api.getImportTemplate(kind['kind']);
        final bytes = base64Decode('${template['content_base64']}');
        final name = '${template['filename']}';
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: name, mimeType: '${template['mimetype']}')],
          fileNameOverrides: [name],
          text: 'Modèle à remplir : ${kind['label']}. Renvoyez-le une fois rempli.',
        );
      });

  Future<void> _import(Map<String, dynamic> kind) async {
    final PickedImportFile? file;
    try {
      file = await widget.pickFile();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
      return;
    }
    if (file == null || !mounted) return;
    final lower = file.name.toLowerCase();
    if (!lower.endsWith('.xlsx') && !lower.endsWith('.csv')) {
      showErrorSnackbar(context, 'Choisissez un fichier Excel (.xlsx) : « ${file.name} » n\'en est pas un.');
      return;
    }
    if (file.bytes.length > _maxBytes) {
      showErrorSnackbar(context, 'Le fichier dépasse 5 Mo : découpez-le.');
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await showConfirmDialog(
      context,
      title: 'Importer ${kind['label']} ?',
      message: '« ${file.name} » dans ${auth.churchName}.\n\n'
          'Le fichier est vérifié en entier : à la moindre erreur, rien n\'est importé.',
      confirmLabel: 'Importer',
    );
    if (!ok || !mounted) return;
    await _busy(kind['kind'], () async {
      final result = await auth.api.runImport(kind['kind'], file!.name, file.bytes);
      if (!mounted) return;
      if (result['ok'] == true) _refreshAfterImport();
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ImportResultScreen(label: '${kind['label']}', result: result)),
      );
    });
  }

  /// Les listes de l'app montrent aussitôt ce qui vient d'être importé.
  void _refreshAfterImport() {
    final org = context.read<OrganizationProvider>();
    org.loadDistricts();
    org.loadCells();
    org.loadAgeGroups();
    context.read<MemberProvider>().loadMembers();
    context.read<DashboardProvider>().load(forceRefresh: true);
    context.read<TodoProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final needsChurch = auth.isSuperAdmin && auth.churchId == 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Importer')),
      body: _loading
          ? const ShimmerList()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (needsChurch)
                      Card(
                        color: AppColors.extended.withValues(alpha: 0.1),
                        child: ListTile(
                          leading: const Icon(Icons.church_outlined),
                          title: const Text('Choisissez d\'abord une église'),
                          subtitle: const Text('Un import se fait dans une église précise.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showChurchPicker(context),
                        ),
                      )
                    else ...[
                      Text(
                        'Téléchargez le modèle, remplissez-le (Excel, WPS, Google Sheets), puis importez-le. '
                        'À la moindre erreur, rien n\'est importé et l\'application dit quelle ligne corriger. '
                        'Une fiche déjà connue est complétée, jamais écrasée.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text('Dans l\'ordre : ${_kinds.map((k) => k['label']).join(' › ')}.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      for (final kind in _kinds)
                        _KindCard(
                          kind: kind,
                          busy: _busyKind == kind['kind'],
                          enabled: _busyKind == null,
                          onDownload: () => _download(kind),
                          onShare: kIsWeb ? null : () => _share(kind),
                          onImport: () => _import(kind),
                        ),
                    ],
                  ],
                ),
    );
  }
}

class _KindCard extends StatelessWidget {
  final Map<String, dynamic> kind;
  final bool busy;
  final bool enabled;
  final VoidCallback onDownload;
  final VoidCallback? onShare;
  final VoidCallback onImport;

  const _KindCard({
    required this.kind,
    required this.busy,
    required this.enabled,
    required this.onDownload,
    required this.onShare,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${kind['label']}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${kind['description'] ?? ''}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: enabled ? onDownload : null,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Modèle'),
                ),
                if (onShare != null)
                  TextButton.icon(
                    onPressed: enabled ? onShare : null,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Partager'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: enabled ? onImport : null,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Importer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Le résultat : ce qui a été importé, ou pourquoi rien ne l'a été.
class ImportResultScreen extends StatelessWidget {
  final String label;
  final Map<String, dynamic> result;
  const ImportResultScreen({super.key, required this.label, required this.result});

  List<String> _lines(String key) =>
      (result[key] is List ? result[key] as List : const []).map((e) => '$e').toList();

  @override
  Widget build(BuildContext context) {
    final ok = result['ok'] == true;
    final errors = _lines('errors');
    final warnings = _lines('warnings');
    final color = ok ? AppColors.integrated : AppColors.abandoned;
    return Scaffold(
      appBar: AppBar(title: Text('Import : $label')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: color.withValues(alpha: 0.1),
            child: ListTile(
              leading: Icon(ok ? Icons.check_circle : Icons.error_outline, color: color, size: 32),
              title: Text(ok ? 'Import réussi' : 'Rien n\'a été importé',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              // Refusé : le titre dit déjà « rien n'a été importé », le sous-titre dit combien corriger.
              subtitle: Text(ok
                  ? '${result['message'] ?? ''}'
                  : '${result['error_count'] ?? errors.length} erreur(s) à corriger dans le fichier.'),
            ),
          ),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionHeader(title: 'À corriger dans le fichier (${errors.length})'),
            for (final line in errors)
              ListTile(
                dense: true,
                leading: const Icon(Icons.close, color: AppColors.abandoned, size: 18),
                title: SelectableText(line),
              ),
            const SizedBox(height: 8),
            Text('Corrigez ces lignes, puis importez à nouveau le fichier.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SectionHeader(title: 'À savoir'),
            for (final line in warnings)
              ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline, size: 18),
                title: SelectableText(line),
              ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Terminé')),
        ],
      ),
    );
  }
}
