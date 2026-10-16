import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';
import 'unit_forms.dart';

/// Les quartiers de l'église : où vivent les membres, ce que couvrent les cellules.
class DistrictListScreen extends StatefulWidget {
  const DistrictListScreen({super.key});

  @override
  State<DistrictListScreen> createState() => _DistrictListScreenState();
}

class _DistrictListScreenState extends State<DistrictListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<OrganizationProvider>().loadDistricts());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationProvider>();
    final districts = provider.districts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quartiers'),
        actions: [
          IconButton(
            icon: Icon(provider.showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined),
            tooltip: provider.showArchived ? 'Masquer les archivés' : 'Afficher les archivés',
            onPressed: () => provider.showArchived = !provider.showArchived,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-district',
        onPressed: () => showDistrictForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau quartier'),
      ),
      body: provider.isLoading && districts.isEmpty
          ? const ShimmerList()
          : provider.error != null && districts.isEmpty
              ? ErrorState(message: provider.error!, onRetry: () => provider.loadDistricts())
              : districts.isEmpty
                  ? const EmptyState(icon: Icons.location_on_outlined, title: 'Aucun quartier')
                  : RefreshIndicator(
                      onRefresh: () => provider.loadDistricts(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: districts.length,
                        itemBuilder: (_, i) {
                          final d = districts[i];
                          final archived = d['active'] == false;
                          final cell = AppConstants.safeStr(d['prayer_cell_name']);
                          final city = AppConstants.safeStr(d['city']);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.location_on_outlined),
                              title: Row(children: [
                                Flexible(child: Text(AppConstants.safeStr(d['name']),
                                    style: TextStyle(color: archived ? Colors.grey : null))),
                                if (archived) const ArchivedChip(),
                              ]),
                              subtitle: Text([
                                if (city.isNotEmpty) city,
                                cell.isEmpty ? 'Aucune cellule' : cell,
                                '${d['member_count'] ?? 0} membre(s)',
                              ].join(' · ')),
                              trailing: const Icon(Icons.edit_outlined, size: 18),
                              onTap: () => showDistrictForm(context, district: d),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
