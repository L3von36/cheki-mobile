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

/// App-style shell: slim status app bar, one focused tab at a time and a
/// Material 3 bottom [NavigationBar] (Home / Accounts / Activity / Banks /
/// Manage / Settings). Each tab keeps its scroll position via [IndexedStack];
/// data refreshes itself every 30s or on pull.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.controller, super.key});

  final AdminController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _ticker;
  int _tab = 0;

  static const _destinations = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Home'),
    (Icons.badge_outlined, Icons.badge_rounded, 'Accounts'),
    (Icons.sensors_rounded, Icons.sensors_rounded, 'Activity'),
    (Icons.account_balance_outlined, Icons.account_balance_rounded, 'Banks'),
    (Icons.admin_panel_settings_outlined, Icons.admin_panel_settings_rounded, 'Manage'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
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
    if (data == null) {
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
    final now = DateTime.now().millisecondsSinceEpoch;

    final tabs = [
      HomeTab(controller: controller, data: data, now: now),
      AccountsTab(controller: controller, data: data, now: now),
      ActivityTab(controller: controller, data: data, now: now),
      BanksTab(controller: controller, data: data),
      ManageTab(controller: controller),
      SettingsTab(
        controller: controller,
        data: data,
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
      appBar: AppBar(
        backgroundColor: AdminColors.background.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 12,
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
                  _tab == i ? _destinations[i].$2 : _destinations[i].$1,
                  size: 22,
                ),
              ),
              label: _destinations[i].$3,
            ),
        ],
      ),
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
}

/// Change-password dialog. On success the Worker rotates every session and
/// returns a fresh token for this device (handled by [AdminController]).
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
