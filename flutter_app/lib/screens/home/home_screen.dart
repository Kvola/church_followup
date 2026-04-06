import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../dashboard/dashboard_screen.dart';
import '../followups/followup_list_screen.dart';
import '../members/member_list_screen.dart';
import '../organization/prayer_cell_list_screen.dart';
import '../organization/age_group_list_screen.dart';
import '../attendance/attendance_sunday_screen.dart';
import '../attendance/attendance_cell_screen.dart';
import '../organization/cooking_rotation_screen.dart';
import '../evangelists/evangelist_list_screen.dart';
import '../admin/mobile_users_screen.dart';
import '../admin/report_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tabs = _buildTabs(auth);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs.map((t) => t.screen).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: tabs
            .map((t) => NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label))
            .toList(),
      ),
      drawer: _buildDrawer(auth),
    );
  }

  List<_TabItem> _buildTabs(AuthProvider auth) {
    switch (auth.userRole) {
      case 'super_admin':
      case 'manager':
        return [
          _TabItem('Accueil', Icons.dashboard_outlined, Icons.dashboard, const DashboardScreen()),
          _TabItem('Suivis', Icons.assignment_outlined, Icons.assignment, const FollowupListScreen()),
          _TabItem('Membres', Icons.people_outlined, Icons.people, const MemberListScreen()),
          _TabItem('Plus', Icons.more_horiz_outlined, Icons.more_horiz, const _MoreScreen()),
        ];
      case 'evangelist':
        return [
          _TabItem('Mes suivis', Icons.assignment_outlined, Icons.assignment, const FollowupListScreen()),
          _TabItem('Membres', Icons.people_outlined, Icons.people, const MemberListScreen()),
          _TabItem('Présence', Icons.checklist_outlined, Icons.checklist, const AttendanceSundayScreen()),
          _TabItem('Plus', Icons.more_horiz_outlined, Icons.more_horiz, const _MoreScreen()),
        ];
      case 'cell_leader':
        return [
          _TabItem('Ma cellule', Icons.groups_outlined, Icons.groups, const PrayerCellListScreen()),
          _TabItem('Membres', Icons.people_outlined, Icons.people, const MemberListScreen()),
          _TabItem('Présence', Icons.checklist_outlined, Icons.checklist, const AttendanceCellScreen()),
          _TabItem('Plus', Icons.more_horiz_outlined, Icons.more_horiz, const _MoreScreen()),
        ];
      case 'group_leader':
        return [
          _TabItem('Mon groupe', Icons.diversity_3_outlined, Icons.diversity_3, const AgeGroupListScreen()),
          _TabItem('Membres', Icons.people_outlined, Icons.people, const MemberListScreen()),
          _TabItem('Plus', Icons.more_horiz_outlined, Icons.more_horiz, const _MoreScreen()),
        ];
      default:
        return [
          _TabItem('Accueil', Icons.home_outlined, Icons.home, const _MoreScreen()),
        ];
    }
  }

  Widget _buildDrawer(AuthProvider auth) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      auth.userName.isNotEmpty ? auth.userName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    auth.userName,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppConstants.roleLabels[auth.userRole] ?? auth.userRole,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                  ),
                  if (auth.churchName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      auth.churchName,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Menu items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (auth.isManager) ...[
                    _drawerItem(Icons.dashboard_outlined, 'Tableau de bord', () => _navigateTo(const DashboardScreen())),
                    _drawerItem(Icons.people_alt_outlined, 'Évangélistes', () => _navigateTo(const EvangelistListScreen())),
                    _drawerItem(Icons.supervisor_account_outlined, 'Utilisateurs', () => _navigateTo(const MobileUsersScreen())),
                    _drawerItem(Icons.assessment_outlined, 'Rapports', () => _navigateTo(const ReportScreen())),
                    const Divider(indent: 16, endIndent: 16),
                  ],
                  _drawerItem(Icons.assignment_outlined, 'Suivis', () => _navigateTo(const FollowupListScreen())),
                  _drawerItem(Icons.people_outlined, 'Membres', () => _navigateTo(const MemberListScreen())),
                  _drawerItem(Icons.groups_outlined, 'Cellules de prière', () => _navigateTo(const PrayerCellListScreen())),
                  _drawerItem(Icons.diversity_3_outlined, 'Groupes d\'âge', () => _navigateTo(const AgeGroupListScreen())),
                  if (auth.isManager) ...[
                    _drawerItem(Icons.restaurant_outlined, 'Rotation cuisine', () => _navigateTo(const CookingRotationScreen())),
                  ],
                  const Divider(indent: 16, endIndent: 16),
                  _drawerItem(Icons.checklist_outlined, 'Présence dimanche', () => _navigateTo(const AttendanceSundayScreen())),
                  _drawerItem(Icons.group_work_outlined, 'Présence cellule', () => _navigateTo(const AttendanceCellScreen())),
                  const Divider(indent: 16, endIndent: 16),
                  _drawerItem(Icons.settings_outlined, 'Paramètres', () => _navigateTo(const SettingsScreen())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context); // close drawer
        onTap();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  void _navigateTo(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;

  _TabItem(this.label, this.icon, this.selectedIcon, this.screen);
}

// ─── More Screen (quick access grid) ─────────────────────────────────

class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    final items = <_QuickAction>[];

    if (auth.isManager) {
      items.addAll([
        _QuickAction('Évangélistes', Icons.people_alt_outlined, AppColors.primary, () => _nav(context, const EvangelistListScreen())),
        _QuickAction('Utilisateurs', Icons.supervisor_account_outlined, AppColors.secondary, () => _nav(context, const MobileUsersScreen())),
        _QuickAction('Rapports', Icons.assessment_outlined, AppColors.integrated, () => _nav(context, const ReportScreen())),
        _QuickAction('Rotation', Icons.restaurant_outlined, AppColors.extended, () => _nav(context, const CookingRotationScreen())),
      ]);
    }

    items.addAll([
      _QuickAction('Cellules', Icons.groups_outlined, AppColors.inProgress, () => _nav(context, const PrayerCellListScreen())),
      _QuickAction('Groupes', Icons.diversity_3_outlined, AppColors.transferred, () => _nav(context, const AgeGroupListScreen())),
      _QuickAction('Présence dim.', Icons.checklist_outlined, AppColors.integrated, () => _nav(context, const AttendanceSundayScreen())),
      _QuickAction('Présence cell.', Icons.group_work_outlined, AppColors.extended, () => _nav(context, const AttendanceCellScreen())),
      _QuickAction('Paramètres', Icons.settings_outlined, Colors.grey, () => _nav(context, const SettingsScreen())),
    ]);

    return Scaffold(
      appBar: AppBar(title: const Text('Plus')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.9,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          return Card(
            child: InkWell(
              onTap: item.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(item.icon, color: item.color, size: 26),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.label,
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _nav(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _QuickAction(this.label, this.icon, this.color, this.onTap);
}
