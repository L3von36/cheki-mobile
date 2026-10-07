import 'dart:async';

import 'package:flutter/material.dart';

import '../admin_api.dart';
import '../admin_controller.dart';
import 'admin_widgets.dart';
import 'theme.dart';
import 'tabs/accounts_tab.dart';
import 'tabs/activity_tab.dart';
import 'tabs/banks_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/manage_tab.dart';
import 'tabs/settings_tab.dart';

String _badgeLabel(int n) => n > 99 ? '99+' : '$n';
String _getEmailInitial(String email) => email.trim().isEmpty ? 'A' : email.trim()[0].toUpperCase();

/// App-style shell: slim status app bar, one focused tab at a time and a
/// Material 3 bottom [NavigationBar] (Home / Accounts / Activity / Banks).
/// Secondary items (Manage / Settings) live in a drawer.
/// Each tab keeps its scroll position via [IndexedStack]; data refreshes
/// itself every 30s or on pull.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.controller, super.key});

  final AdminController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Timer? _ticker;
  int _tab = 0;

  static final _destinations = [
    _Destination(
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
      label: 'Home',
    ),
    _Destination(
      icon: Icons.badge_outlined,
      selectedIcon: Icons.badge_rounded,
      label: 'Accounts',
    ),
    _Destination(
      icon: Icons.sensors_rounded,
      selectedIcon: Icons.sensors_rounded,
      label: 'Activity',
    ),
    _Destination(
      icon: Icons.account_balance_outlined,
      selectedIcon: Icons.account_balance_rounded,
      label: 'Banks',
    ),
  ];

  static const _drawerItems = [
    _DrawerItem(
      icon: Icons.admin_panel_settings_outlined,
      selectedIcon: Icons.admin_panel_settings_rounded,
      label: 'Manage',
      index: 4,
    ),
    _DrawerItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: 'Settings',
      index: 5,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await widget.controller.refresh();
  }

  Future<void> _confirmSignOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdminColors.border),
        ),
        title: const Text('Sign out?', style: TextStyle(fontSize: 17)),
        content: const Text(
          'This device keeps no credentials after sign-out. '
          'Sign back in with the owner email and password.',
          style: TextStyle(fontSize: 13.5, height: 1.45, color: AdminColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out', style: TextStyle(color: AdminColors.rose)),
          ),
        ],
      ),
    );
    if (yes == true) await widget.controller.signOut();
  }

  Future<void> _showChangePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ChangePasswordDialog(controller: widget.controller),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdminColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AdminColors.border),
          ),
          content: const Text(
            'Password changed. Other devices were signed out.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final data = controller.overview;
    final isLoading = data == null && controller.busy;
    final loadFailed = data == null && controller.error != null;

    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AdminColors.emerald,
            ),
          ),
        ),
      );
    }

    if (loadFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 38, color: AdminColors.faint),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load dashboard',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  controller.error ?? 'Unknown error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.5, color: AdminColors.muted),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: controller.refresh,
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: controller.signOut,
                  child: const Text('Sign out', style: TextStyle(color: AdminColors.muted)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final tabs = [
      HomeTab(controller: controller, data: data!, now: now),
      AccountsTab(controller: controller, data: data!, now: now),
      ActivityTab(controller: controller, data: data!, now: now),
      BanksTab(controller: controller, data: data!),
      ManageTab(controller: controller),
      SettingsTab(
        controller: controller,
        data: data!,
        onChangePassword: _showChangePassword,
        onSignOut: _confirmSignOut,
      ),
    ];

    final titles = const [
      'Home',
      'Accounts',
      'Activity',
      'Banks',
      'Manage',
      'Settings',
    ];

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: AdminColors.background.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 12,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, size: 24),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: 'Menu',
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset('assets/seal.png', width: 34, height: 34, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mahtem Admin · ${titles[_tab]}',
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.15),
                ),
                Text(
                  controller.email ?? 'mahtem-api · Cloudflare Workers',
                  style: const TextStyle(
                      fontSize: 10.5, color: AdminColors.faint, height: 1.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
        actions: [
          LiveToggle(on: controller.autoRefresh, onChanged: controller.setAutoRefresh),
          IconButton(
            onPressed: controller.busy ? null : _refresh,
            tooltip: 'Refresh now',
            icon: controller.busy
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AdminColors.emerald),
                  )
                : const Icon(Icons.refresh_rounded, size: 22, color: AdminColors.muted),
          ),
          IconButton(
            onPressed: controller.busy ? null : _showChangePassword,
            tooltip: 'Change password',
            icon: const Icon(Icons.lock_reset_outlined,
                size: 21, color: AdminColors.muted),
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AdminColors.border),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          // The Manage tab fetches its own documents lazily — once when
          // first opened, then only on pull-to-refresh / manual reload.
          if (i == 4) controller.loadManageDataIfStale();
        },
        height: 64,
        backgroundColor: AdminColors.card,
        indicatorColor: AdminColors.emerald.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        destinations: [
          for (var i = 0; i < _destinations.length; i++)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _badgeFor(data, i) > 0,
                label: Text(
                  _badgeLabel(_badgeFor(data, i)),
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF052E22)),
                ),
                backgroundColor: _tab == i ? AdminColors.emerald : AdminColors.muted,
                offset: const Offset(3, -4),
                child: Icon(
                  _tab == i ? _destinations[i].selectedIcon : _destinations[i].icon,
                  size: 22,
                ),
              ),
              label: _destinations[i].label,
            ),
        ],
      ),
      drawer: _buildDrawer(context),
    );
  }

  int _badgeFor(AdminOverview data, int tab) {
    switch (tab) {
      case 0:
        return data.totals.accounts;
      case 1:
        return data.totals.accounts;
      case 2:
        return data.recent.length;
      default:
        return 0;
    }
  }

  String _badgeLabel(int n) => n > 99 ? '99+' : '$n';

  Widget _buildDrawer(BuildContext context) {
    final controller = widget.controller;
    final data = controller.overview!;

    return Drawer(
      backgroundColor: AdminColors.background,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AdminColors.border, width: 1)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/seal.png', width: 36, height: 36, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mahtem Admin', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AdminColors.text)),
                        Text('Owner Console', style: TextStyle(fontSize: 11, color: AdminColors.faint)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            _DrawerSection(
              title: 'MAIN',
              children: [
                for (int i = 0; i < _destinations.length; i++)
                  _DrawerTile(
                    destination: _destinations[i],
                    selected: _tab == i,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _tab = i);
                    },
                    badge: _badgeFor(data, i),
                  ),
              ],
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            _DrawerSection(
              title: 'ADMINISTRATION',
              children: [
                for (final item in _drawerItems)
                  _DrawerTile(
                    destination: _Destination(icon: item.icon, selectedIcon: item.selectedIcon, label: item.label),
                    selected: _tab == item.index,
                    onTap: () {
                      Navigator.pop(context);
                      if (item.index == 4) controller.loadManageDataIfStale();
                      setState(() => _tab = item.index);
                    },
                  ),
              ],
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminColors.emerald.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminColors.emerald.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AdminColors.emerald.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AdminColors.emerald.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            _getEmailInitial(controller.email ?? 'A'),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.emerald),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(controller.email ?? 'Owner', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              Text(
                                controller.isOwner ? 'Owner · full access · sessions last 30 days' : 'Admin · analytics, accounts & announcements',
                                style: TextStyle(fontSize: 11, color: AdminColors.faint),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign out'),
                      onPressed: _confirmSignOut,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminColors.rose,
                        side: BorderSide(color: AdminColors.rose),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    }
}

/// Change-password dialog. On success the Worker rotates every session and
/// returns a fresh token for this device (handled by [AdminController]).
class _Destination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _Destination({required this.icon, required this.selectedIcon, required this.label});
}

class _DrawerItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;
  const _DrawerItem({required this.icon, required this.selectedIcon, required this.label, required this.index});
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AdminColors.faint)),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AdminColors.emerald.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(selected ? destination.selectedIcon : destination.icon, size: 22, color: selected ? AdminColors.emerald : AdminColors.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(destination.label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? AdminColors.emerald : AdminColors.text))),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AdminColors.emerald,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _badgeLabel(badge),
                    style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    }
  }

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.controller});

  final AdminController controller;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    final ok = await widget.controller.changePassword(_current.text, _next.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = widget.controller.error);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AdminColors.border),
      ),
      title: const Text('Change password', style: TextStyle(fontSize: 17)),
      content: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final busy = widget.controller.busy;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _current,
                obscureText: _obscure,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: 'Current password',
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      size: 19, color: AdminColors.faint),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _next,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: 'New password (10+ characters)',
                  prefixIcon: Icon(Icons.lock_reset_outlined,
                      size: 19, color: AdminColors.faint),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) {
                  if (!busy) _submit();
                },
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Repeat new password',
                  prefixIcon: const Icon(Icons.lock_person_rounded,
                      size: 19, color: AdminColors.faint),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 19,
                      color: AdminColors.faint,
                    ),
                    tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 12.5, color: AdminColors.rose),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final busy = widget.controller.busy;
            return TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
            );
          },
        ),
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final busy = widget.controller.busy;
            return FilledButton(
              onPressed: busy ? null : _submit,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Color(0xFF052E22)),
                    )
                  : const Text('Change'),
            );
          },
        ),
      ],
    );
  }
}
