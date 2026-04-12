import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dashboard = context.watch<DashboardProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          dashboard.dashboard?['church_name'] ??
              (auth.churchName.isNotEmpty ? auth.churchName : 'Tableau de bord'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => dashboard.load(forceRefresh: true),
          ),
        ],
      ),
      drawer: null, // Managed by HomeScreen
      body: dashboard.isLoading && dashboard.dashboard == null
          ? const ShimmerList(itemCount: 4)
          : dashboard.error != null && dashboard.dashboard == null
              ? ErrorState(message: dashboard.error!, onRetry: () => dashboard.load(forceRefresh: true))
              : RefreshIndicator(
                  onRefresh: () => dashboard.load(forceRefresh: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      // Greeting
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Bonjour, ${auth.userName.split(' ').first} 👋',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Stats grid
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        children: [
                          StatCard(
                            label: 'Membres',
                            value: '${dashboard.totalMembers}',
                            icon: Icons.people,
                            color: AppColors.primary,
                          ),
                          StatCard(
                            label: 'Évangélistes',
                            value: '${dashboard.totalEvangelists}',
                            icon: Icons.person_pin,
                            color: AppColors.inProgress,
                          ),
                          StatCard(
                            label: 'Cellules',
                            value: '${dashboard.totalCells}',
                            icon: Icons.groups,
                            color: AppColors.extended,
                          ),
                          StatCard(
                            label: 'Groupes',
                            value: '${dashboard.totalGroups}',
                            icon: Icons.diversity_3,
                            color: AppColors.transferred,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Integration rate card
                      _IntegrationRateCard(
                        rate: dashboard.integrationRate,
                        integrated: dashboard.integratedCount,
                        abandoned: dashboard.abandonedCount,
                        active: dashboard.activeFollowups,
                      ),
                      const SizedBox(height: 20),

                      // Followup overview
                      _FollowupOverviewCard(
                        active: dashboard.activeFollowups,
                        integrated: dashboard.integratedCount,
                        abandoned: dashboard.abandonedCount,
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _IntegrationRateCard extends StatelessWidget {
  final double rate;
  final int integrated;
  final int abandoned;
  final int active;

  const _IntegrationRateCard({
    required this.rate,
    required this.integrated,
    required this.abandoned,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rateColor = rate >= 70
        ? AppColors.integrated
        : rate >= 40
            ? AppColors.extended
            : AppColors.abandoned;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Taux d\'intégration', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: rate / 100,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: rateColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(rateColor),
                      ),
                      Center(
                        child: Text(
                          '${rate.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: rateColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      _statRow('En cours', '$active', AppColors.inProgress),
                      const SizedBox(height: 8),
                      _statRow('Intégrés', '$integrated', AppColors.integrated),
                      const SizedBox(height: 8),
                      _statRow('Abandonnés', '$abandoned', AppColors.abandoned),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
      ],
    );
  }
}

class _FollowupOverviewCard extends StatelessWidget {
  final int active;
  final int integrated;
  final int abandoned;

  const _FollowupOverviewCard({
    required this.active,
    required this.integrated,
    required this.abandoned,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = active + integrated + abandoned;

    if (total == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Répartition des suivis', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 40,
                  sections: [
                    if (active > 0)
                      PieChartSectionData(
                        value: active.toDouble(),
                        title: '$active',
                        color: AppColors.inProgress,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    if (integrated > 0)
                      PieChartSectionData(
                        value: integrated.toDouble(),
                        title: '$integrated',
                        color: AppColors.integrated,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    if (abandoned > 0)
                      PieChartSectionData(
                        value: abandoned.toDouble(),
                        title: '$abandoned',
                        color: AppColors.abandoned,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend('En cours', AppColors.inProgress),
                const SizedBox(width: 16),
                _legend('Intégrés', AppColors.integrated),
                const SizedBox(width: 16),
                _legend('Abandonnés', AppColors.abandoned),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
