import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/church_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rapports PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _reportTile(
            icon: Icons.track_changes,
            title: 'Rapport de Suivi',
            subtitle: 'Détails de tous les suivis par évangéliste',
            onTap: () => _showEvangelistPicker('followup'),
          ),
          _reportTile(
            icon: Icons.dashboard,
            title: 'Tableau de Bord Église',
            subtitle: 'Statistiques globales de la communauté',
            onTap: () => _generateDashboardReport(),
          ),
          _reportTile(
            icon: Icons.home_work,
            title: 'Membres par Cellule',
            subtitle: 'Liste des membres de chaque cellule',
            onTap: () => _generateCellReport(),
          ),
          _reportTile(
            icon: Icons.groups,
            title: "Membres par Groupe d'Âge",
            subtitle: 'Liste des membres de chaque groupe',
            onTap: () => _generateGroupReport(),
          ),
        ],
      ),
    );
  }

  Widget _reportTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.picture_as_pdf, color: Colors.red),
        onTap: onTap,
      ),
    );
  }

  Future<void> _showEvangelistPicker(String reportType) async {
    final service = context.read<ChurchService>();
    final evangelists = await service.getEvangelists();
    if (!mounted) return;

    final selected = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Choisir un évangéliste'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: evangelists.length,
            itemBuilder: (_, i) {
              final e = evangelists[i];
              return ListTile(
                title: Text(e['name'] ?? ''),
                onTap: () => Navigator.pop(context, e['id']),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null) {
      _generateFollowupReport(selected);
    }
  }

  Future<void> _generateFollowupReport(int evangelistId) async {
    final service = context.read<ChurchService>();
    final report = await service.getFollowupReport(evangelistId);
    if (report.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune donnée')));
      return;
    }

    await Printing.layoutPdf(onLayout: (format) async {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Header(level: 0, text: 'Rapport de Suivi - ${report['evangelist_name'] ?? ''}'),
            pw.Paragraph(text: 'Date: ${DateTime.now().toString().split(' ')[0]}'),
            pw.SizedBox(height: 10),
            if (report['followups'] is List)
              ...((report['followups'] as List).map<pw.Widget>((f) => pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('${f['reference'] ?? ''} - ${f['member_name'] ?? ''}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('État: ${f['state'] ?? ''} | Progression: ${f['progress'] ?? 0}%'),
                        pw.Text('Semaine: ${f['current_week'] ?? 0}/${f['total_weeks'] ?? 4}'),
                        pw.Text('Score moyen: ${f['average_score'] ?? 0}/10'),
                      ],
                    ),
                  ))),
          ],
        ),
      );
      return pdf.save();
    });
  }

  Future<void> _generateDashboardReport() async {
    final service = context.read<ChurchService>();
    final d = await service.getDashboard();
    if (d.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune donnée')));
      return;
    }

    await Printing.layoutPdf(onLayout: (format) async {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 0, text: 'Tableau de Bord - ${d['church_name'] ?? ''}'),
              pw.Paragraph(text: 'Date: ${DateTime.now().toString().split(' ')[0]}'),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headers: ['Indicateur', 'Valeur'],
                data: [
                  ['Membres totaux', '${d['total_members'] ?? 0}'],
                  ['Évangélistes', '${d['total_evangelists'] ?? 0}'],
                  ['Cellules de prière', '${d['total_cells'] ?? 0}'],
                  ["Groupes d'âge", '${d['total_groups'] ?? 0}'],
                  ['Suivis actifs', '${d['active_followups'] ?? 0}'],
                  ['Intégrés', '${d['integrated_count'] ?? 0}'],
                  ['Abandonnés', '${d['abandoned_count'] ?? 0}'],
                  ["Taux d'intégration", '${d['integration_rate'] ?? 0}%'],
                ],
              ),
            ],
          ),
        ),
      );
      return pdf.save();
    });
  }

  Future<void> _generateCellReport() async {
    final service = context.read<ChurchService>();
    final cells = await service.getPrayerCells();
    if (cells.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune donnée')));
      return;
    }

    await Printing.layoutPdf(onLayout: (format) async {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Header(level: 0, text: 'Membres par Cellule de Prière'),
            pw.Paragraph(text: 'Date: ${DateTime.now().toString().split(' ')[0]}'),
            ...cells.map<pw.Widget>((cell) {
              final members = cell['members'] as List? ?? [];
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 15),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Header(level: 1, text: '${cell['name'] ?? ''} (${members.length} membres)'),
                    if (cell['leader_name'] != null) pw.Text('Leader: ${cell['leader_name']}'),
                    pw.SizedBox(height: 5),
                    if (members.isNotEmpty)
                      pw.Table.fromTextArray(
                        headers: ['Nom', 'Téléphone'],
                        data: members.map<List<String>>((m) => [m['name'] ?? '', m['phone'] ?? '']).toList(),
                      )
                    else
                      pw.Text('Aucun membre', style: const pw.TextStyle(color: PdfColors.grey)),
                  ],
                ),
              );
            }),
          ],
        ),
      );
      return pdf.save();
    });
  }

  Future<void> _generateGroupReport() async {
    final service = context.read<ChurchService>();
    final groups = await service.getAgeGroups();
    if (groups.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune donnée')));
      return;
    }

    await Printing.layoutPdf(onLayout: (format) async {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Header(level: 0, text: "Membres par Groupe d'Âge"),
            pw.Paragraph(text: 'Date: ${DateTime.now().toString().split(' ')[0]}'),
            ...groups.map<pw.Widget>((group) {
              final members = group['members'] as List? ?? [];
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 15),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Header(level: 1, text: '${group['name'] ?? ''} (${members.length} membres)'),
                    if (group['group_type'] != null) pw.Text('Type: ${group['group_type']}'),
                    if (group['leader_name'] != null) pw.Text('Leader: ${group['leader_name']}'),
                    pw.SizedBox(height: 5),
                    if (members.isNotEmpty)
                      pw.Table.fromTextArray(
                        headers: ['Nom', 'Téléphone'],
                        data: members.map<List<String>>((m) => [m['name'] ?? '', m['phone'] ?? '']).toList(),
                      )
                    else
                      pw.Text('Aucun membre', style: const pw.TextStyle(color: PdfColors.grey)),
                  ],
                ),
              );
            }),
          ],
        ),
      );
      return pdf.save();
    });
  }
}
