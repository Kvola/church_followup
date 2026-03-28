import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';
import 'followup_list_screen.dart';
import 'member_list_screen.dart';
import 'attendance_sunday_screen.dart';
import 'attendance_cell_screen.dart';
import 'prayer_cell_list_screen.dart';
import 'age_group_list_screen.dart';
import 'cooking_rotation_screen.dart';
import 'evangelist_list_screen.dart';
import 'dashboard_screen.dart';
import 'mobile_users_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ChurchService>();
    final role = service.userRole ?? 'evangelist';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi Évangélisation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(role),
      bottomNavigationBar: _buildBottomNav(role),
    );
  }

  Widget _buildBody(String role) {
    switch (role) {
      case 'manager':
        return _buildManagerBody();
      case 'evangelist':
        return _buildEvangelistBody();
      case 'cell_leader':
        return _buildCellLeaderBody();
      case 'group_leader':
        return _buildGroupLeaderBody();
      default:
        return _buildEvangelistBody();
    }
  }

  Widget _buildManagerBody() {
    switch (_currentIndex) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const FollowupListScreen();
      case 2:
        return const MemberListScreen();
      case 3:
        return const ManagerMoreScreen();
      default:
        return const DashboardScreen();
    }
  }

  Widget _buildEvangelistBody() {
    switch (_currentIndex) {
      case 0:
        return const FollowupListScreen(myOnly: true);
      case 1:
        return const MemberListScreen();
      case 2:
        return const AttendanceSundayScreen();
      default:
        return const FollowupListScreen(myOnly: true);
    }
  }

  Widget _buildCellLeaderBody() {
    switch (_currentIndex) {
      case 0:
        return const PrayerCellDetailLeaderScreen();
      case 1:
        return const AttendanceCellScreen();
      case 2:
        return const MemberListScreen();
      default:
        return const PrayerCellDetailLeaderScreen();
    }
  }

  Widget _buildGroupLeaderBody() {
    switch (_currentIndex) {
      case 0:
        return const AgeGroupDetailLeaderScreen();
      case 1:
        return const MemberListScreen();
      default:
        return const AgeGroupDetailLeaderScreen();
    }
  }

  Widget? _buildBottomNav(String role) {
    switch (role) {
      case 'manager':
        return NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'Tableau'),
            NavigationDestination(icon: Icon(Icons.track_changes), label: 'Suivis'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Membres'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Plus'),
          ],
        );
      case 'evangelist':
        return NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.track_changes), label: 'Mes Suivis'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Membres'),
            NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Présences'),
          ],
        );
      case 'cell_leader':
        return NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_work), label: 'Ma Cellule'),
            NavigationDestination(icon: Icon(Icons.check_circle), label: 'Présences'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Membres'),
          ],
        );
      case 'group_leader':
        return NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.groups), label: 'Mon Groupe'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Membres'),
          ],
        );
      default:
        return null;
    }
  }
}

class ManagerMoreScreen extends StatelessWidget {
  const ManagerMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tile(context, Icons.person_pin, 'Évangélistes', const EvangelistListScreen()),
        _tile(context, Icons.home_work, 'Cellules de Prière', const PrayerCellListScreen()),
        _tile(context, Icons.groups, "Groupes d'Âge", const AgeGroupListScreen()),
        _tile(context, Icons.calendar_today, 'Présences Dimanche', const AttendanceSundayScreen()),
        _tile(context, Icons.check_circle, 'Présences Cellule', const AttendanceCellScreen()),
        _tile(context, Icons.restaurant, 'Rotation Cuisine', const CookingRotationScreen()),
        _tile(context, Icons.admin_panel_settings, 'Utilisateurs Mobile', const MobileUsersScreen()),
        _tile(context, Icons.picture_as_pdf, 'Rapports PDF', const ReportScreen()),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, Widget screen) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      ),
    );
  }
}

class PrayerCellDetailLeaderScreen extends StatefulWidget {
  const PrayerCellDetailLeaderScreen({super.key});

  @override
  State<PrayerCellDetailLeaderScreen> createState() => _PrayerCellDetailLeaderScreenState();
}

class _PrayerCellDetailLeaderScreenState extends State<PrayerCellDetailLeaderScreen> {
  Map<String, dynamic>? _cellData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = context.read<ChurchService>();
    final cells = await service.getPrayerCells();
    if (cells.isNotEmpty && mounted) {
      setState(() {
        _cellData = cells.first;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_cellData == null) return const Center(child: Text('Aucune cellule assignée'));

    final members = _cellData!['members'] as List? ?? [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_cellData!['name'] ?? '', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('${members.length} membre(s)'),
                  if (_cellData!['meeting_day'] != null)
                    Text('Réunion: ${_cellData!['meeting_day']} à ${_cellData!['meeting_time'] ?? ''}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Membres', style: Theme.of(context).textTheme.titleMedium),
          ...members.map<Widget>((m) => Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text((m['name'] ?? '?')[0])),
                  title: Text(m['name'] ?? ''),
                  subtitle: Text(m['phone'] ?? ''),
                ),
              )),
        ],
      ),
    );
  }
}

class AgeGroupDetailLeaderScreen extends StatefulWidget {
  const AgeGroupDetailLeaderScreen({super.key});

  @override
  State<AgeGroupDetailLeaderScreen> createState() => _AgeGroupDetailLeaderScreenState();
}

class _AgeGroupDetailLeaderScreenState extends State<AgeGroupDetailLeaderScreen> {
  Map<String, dynamic>? _groupData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = context.read<ChurchService>();
    final groups = await service.getAgeGroups();
    if (groups.isNotEmpty && mounted) {
      setState(() {
        _groupData = groups.first;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_groupData == null) return const Center(child: Text('Aucun groupe assigné'));

    final members = _groupData!['members'] as List? ?? [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_groupData!['name'] ?? '', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (_groupData!['group_type'] != null) Text('Type: ${_groupData!['group_type']}'),
                  Text('${members.length} membre(s)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Membres', style: Theme.of(context).textTheme.titleMedium),
          ...members.map<Widget>((m) => Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text((m['name'] ?? '?')[0])),
                  title: Text(m['name'] ?? ''),
                  subtitle: Text(m['phone'] ?? ''),
                ),
              )),
        ],
      ),
    );
  }
}
