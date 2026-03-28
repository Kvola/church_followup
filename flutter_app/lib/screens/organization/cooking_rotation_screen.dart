import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

class CookingRotationScreen extends StatefulWidget {
  const CookingRotationScreen({super.key});

  @override
  State<CookingRotationScreen> createState() => _CookingRotationScreenState();
}

class _CookingRotationScreenState extends State<CookingRotationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrganizationProvider>().loadCookingRotation();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotation cuisine'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => provider.loadCookingRotation()),
        ],
      ),
      body: provider.isLoading && provider.cookingRotation.isEmpty
          ? const ShimmerList()
          : provider.error != null && provider.cookingRotation.isEmpty
              ? ErrorState(message: provider.error!, onRetry: () => provider.loadCookingRotation())
              : provider.cookingRotation.isEmpty
                  ? const EmptyState(icon: Icons.restaurant_outlined, title: 'Aucune rotation planifiée')
                  : RefreshIndicator(
                      onRefresh: () => provider.loadCookingRotation(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.cookingRotation.length,
                        itemBuilder: (_, index) {
                          final item = provider.cookingRotation[index];
                          final state = item['state'] ?? 'planned';
                          final stateColor = state == 'done'
                              ? AppColors.integrated
                              : state == 'cancelled'
                                  ? AppColors.abandoned
                                  : AppColors.extended;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: stateColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.restaurant, color: stateColor, size: 22),
                              ),
                              title: Text(item['cell_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(item['date'] ?? ''),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: stateColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  AppConstants.cookingStateLabels[state] ?? state,
                                  style: TextStyle(color: stateColor, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
