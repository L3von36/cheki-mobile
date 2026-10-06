import 'package:flutter/material.dart';

import '../../admin_api.dart';
import '../../admin_controller.dart';
import '../../format.dart';
import '../admin_widgets.dart';
import '../theme.dart';

/// Manage tab (v1.19 console) — the operations hub:
///   * service controls: sign-ups + maintenance mode (owner only),
///   * announcements: broadcast a banner into every user's app,
///   * admin users: invite / reset / remove additional sign-ins (owner),
///   * audit trail: every management action, newest first.
///
/// The server enforces roles on every call — the UI only mirrors them.
class ManageTab extends StatelessWidget {
  const ManageTab({required this.controller, super.key});

  final AdminController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.settings;
        final users = controller.users;
        final announcements = controller.announcements;
        final audit = controller.auditEntries;
        final owner = controller.isOwner;

        return RefreshIndicator(
          color: AdminColors.emerald,
          backgroundColor: AdminColors.card,
          onRefresh: controller.loadManageData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Text(
                'Server-side switches, broadcasts and the audit trail — '
                'the Worker enforces every action',
                style: const TextStyle(fontSize: 12.5, color: AdminColors.muted),
              ),
              if (controller.manageError != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: controller.manageError!),
              ],
              const SizedBox(height: 12),

              _ServiceControlsCard(controller: controller, settings: settings),
              const SizedBox(height: 12),
              _AnnouncementsCard(
                controller: controller,
                announcements: announcements,
              ),
              const SizedBox(height: 12),
              if (users != null) ...[
                _AdminUsersCard(controller: controller, users: users, owner: owner),
                const SizedBox(height: 12),
              ],
              _AuditCard(entries: audit),
              const SizedBox(height: 12),
              const PrivacyCard(),
            ],
          ),
        );
      },
    );
  }
}

// ── error banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdminColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 15, color: AdminColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.4, color: AdminColors.amber),
            ),
          ),
        ],
      ),
    );
  }
}

// ── service controls ─────────────────────────────────────────────────────────

class _ServiceControlsCard extends StatelessWidget {
  const _ServiceControlsCard({required this.controller, required this.settings});

  final AdminController controller;
  final AdminSettings? settings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.tune_rounded,
              title: 'Service controls',
              subtitle: controller.isOwner
                  ? 'Global switches, enforced by the Worker in real time'
                  : 'Owner only — showing the current server state',
            ),
            const SizedBox(height: 10),
            if (s == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AdminColors.emerald),
                  ),
                ),
              )
            else ...[
              _switchRow(
                context: context,
                icon: Icons.person_add_rounded,
                title: 'Allow new sign-ups',
                subtitleOn: 'New user accounts can be created',
                subtitleOff: 'Sign-up attempts are refused — existing accounts unaffected',
                value: s.signupsEnabled,
                busy: controller.manageBusy,
                canEdit: controller.isOwner,
                onChanged: (v) => controller.updateSettings(signupsEnabled: v),
              ),
              const Divider(height: 1, color: AdminColors.border),
              _switchRow(
                context: context,
                icon: Icons.construction_rounded,
                title: 'Maintenance mode',
                subtitleOn: 'Vault uploads answer 503 — users keep verifying on-device',
                subtitleOff: 'Cloud sync fully operational',
                value: s.maintenanceMode,
                busy: controller.manageBusy,
                canEdit: controller.isOwner,
                danger: true,
                onChanged: (v) => controller.updateSettings(maintenanceMode: v),
              ),
              if (s.updatedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Last changed ${timeAgo(s.updatedAt)}'
                  '${s.updatedBy != null ? ' · by ${s.updatedBy}' : ''}',
                  style: const TextStyle(
                      fontSize: 10.5, color: Color(0xFF52525B)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _switchRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitleOn,
    required String subtitleOff,
    required bool value,
    required bool busy,
    required bool canEdit,
    required ValueChanged<bool> onChanged,
    bool danger = false,
  }) {
    final activeColor = danger ? AdminColors.amber : AdminColors.emerald;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, size: 20, color: value ? activeColor : AdminColors.faint),
      title: Text(title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
      subtitle: Text(
        value ? subtitleOn : subtitleOff,
        style: TextStyle(
            fontSize: 11.5, height: 1.35, color: value ? activeColor : AdminColors.faint),
      ),
      value: value,
      onChanged: busy || !canEdit ? null : onChanged,
    );
  }
}

// ── announcements ────────────────────────────────────────────────────────────

class _AnnouncementsCard extends StatelessWidget {
  const _AnnouncementsCard({required this.controller, required this.announcements});

  final AdminController controller;
  final List<Announcement>? announcements;

  @override
  Widget build(BuildContext context) {
    final list = announcements;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: SectionHeader(
                    icon: Icons.campaign_rounded,
                    title: 'Announcements',
                    subtitle: 'A banner every user sees on their next app launch',
                  ),
                ),
                IconButton(
                  tooltip: 'New announcement',
                  onPressed: controller.manageBusy
                      ? null
                      : () => _showAnnouncementDialog(context),
                  icon: const Icon(Icons.add_rounded,
                      size: 22, color: AdminColors.emerald),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (list == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AdminColors.emerald),
                  ),
                ),
              )
            else if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No announcements live. Post one to reach every device — '
                  'info for notes, warn for degraded service, critical for '
                  'emergencies. At most 5 can be stored.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.5, color: AdminColors.faint),
                ),
              )
            else
              for (final a in list)
                _AnnouncementTile(
                  announcement: a,
                  busy: controller.manageBusy,
                  onDelete: () => _confirmDelete(context, a),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAnnouncementDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AnnouncementDialog(controller: controller),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AdminColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdminColors.border),
        ),
        title: const Text('Delete announcement?', style: TextStyle(fontSize: 16)),
        content: Text(
          '“${a.message.length > 90 ? '${a.message.substring(0, 90)}…' : a.message}” '
          'disappears from every device on its next launch.',
          style: const TextStyle(fontSize: 13, height: 1.45, color: AdminColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: AdminColors.rose)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteAnnouncement(a.id);
    }
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({
    required this.announcement,
    required this.busy,
    required this.onDelete,
  });

  final Announcement announcement;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final (color, icon) = a.isCritical
        ? (AdminColors.rose, Icons.dangerous_rounded)
        : a.isWarn
            ? (AdminColors.amber, Icons.warning_rounded)
            : (AdminColors.emerald, Icons.info_outline_rounded);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C0E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.message,
                    style: const TextStyle(fontSize: 12.5, height: 1.45),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_levelLabel(a.level)} · posted ${timeAgo(a.createdAt)}'
                    '${a.createdBy != null ? ' · by ${a.createdBy}' : ''}',
                    style: const TextStyle(
                        fontSize: 10, color: AdminColors.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Delete announcement',
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 17, color: AdminColors.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _levelLabel(String level) => switch (level) {
        'critical' => 'CRITICAL',
        'warn' => 'WARNING',
        _ => 'INFO',
      };
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog({required this.controller});

  final AdminController controller;

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _message = TextEditingController();
  String _level = 'info';
  String? _error;

  static const _levels = [
    ('info', 'Info', Icons.info_outline_rounded, AdminColors.emerald),
    ('warn', 'Warn', Icons.warning_rounded, AdminColors.amber),
    ('critical', 'Critical', Icons.dangerous_rounded, AdminColors.rose),
  ];

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _message.text.trim();
    if (text.length < 3 || text.length > 500) {
      setState(() => _error = 'Message must be 3-500 characters.');
      return;
    }
    final ok = await widget.controller.createAnnouncement(text, _level);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.controller.manageError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.manageBusy;
        return AlertDialog(
          backgroundColor: AdminColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AdminColors.border),
          ),
          title: const Text('New announcement', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _message,
                autofocus: true,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: 'What should every user see?',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final (id, label, icon, color) in _levels)
                    ChoiceChip(
                      avatar: Icon(icon, size: 15, color: _level == id ? const Color(0xFF052E22) : color),
                      label: Text(label),
                      selected: _level == id,
                      onSelected: busy ? null : (_) => setState(() => _level = id),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: _level == id ? FontWeight.w600 : FontWeight.w400,
                        color: _level == id ? const Color(0xFF052E22) : AdminColors.muted,
                      ),
                      selectedColor: color,
                      showCheckmark: false,
                      side: BorderSide(
                        color: _level == id ? color : AdminColors.border,
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(fontSize: 12.5, color: AdminColors.rose)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
            ),
            FilledButton(
              onPressed: busy ? null : _post,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Color(0xFF052E22)),
                    )
                  : const Text('Post'),
            ),
          ],
        );
      },
    );
  }
}

// ── admin users ──────────────────────────────────────────────────────────────

class _AdminUsersCard extends StatelessWidget {
  const _AdminUsersCard({
    required this.controller,
    required this.users,
    required this.owner,
  });

  final AdminController controller;
  final AdminUsersDoc users;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SectionHeader(
                    icon: Icons.group_rounded,
                    title: 'Console access',
                    subtitle: owner
                        ? 'The owner account plus additional admins (max 25)'
                        : 'Read-only — managing admins needs the owner account',
                  ),
                ),
                if (owner)
                  IconButton(
                    tooltip: 'Add admin',
                    onPressed: controller.manageBusy
                        ? null
                        : () => _showAddDialog(context),
                    icon: const Icon(Icons.person_add_alt_rounded,
                        size: 21, color: AdminColors.emerald),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (users.ownerEmail != null)
              _AdminRow(
                avatar: 'O',
                email: users.ownerEmail!,
                detail: 'Owner · created ${fmtDate(users.ownerCreatedAt)}',
              ),
            if (users.ownerEmail != null && users.admins.isNotEmpty)
              const Divider(height: 1, color: AdminColors.border),
            if (users.admins.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  users.ownerEmail != null
                      ? 'No additional admins — the owner is the only sign-in.'
                      : 'No admin accounts.',
                  style: const TextStyle(fontSize: 12.5, color: AdminColors.faint),
                ),
              )
            else
              for (final u in users.admins)
                _AdminRow(
                  avatar: 'A',
                  email: u.email,
                  detail: 'Admin · created ${fmtDate(u.createdAt)}'
                      '${u.createdBy != null ? ' · by ${u.createdBy}' : ''}',
                  actions: owner
                      ? [
                          IconButton(
                            tooltip: 'Reset password',
                            onPressed: controller.manageBusy
                                ? null
                                : () => _showResetDialog(context, u),
                            icon: const Icon(Icons.key_rounded,
                                size: 17, color: AdminColors.faint),
                          ),
                          IconButton(
                            tooltip: 'Remove admin',
                            onPressed: controller.manageBusy
                                ? null
                                : () => _confirmRemove(context, u),
                            icon: const Icon(Icons.person_remove_alt_1_rounded,
                                size: 18, color: AdminColors.faint),
                          ),
                        ]
                      : null,
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AddAdminDialog(controller: controller),
    );
  }

  Future<void> _showResetDialog(BuildContext context, AdminUser user) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ResetAdminDialog(controller: controller, user: user),
    );
  }

  Future<void> _confirmRemove(BuildContext context, AdminUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AdminColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdminColors.border),
        ),
        title: const Text('Remove admin?', style: TextStyle(fontSize: 16)),
        content: Text(
          '${user.email} loses console access immediately (their sessions '
          'are revoked). The owner account is untouched.',
          style: const TextStyle(
              fontSize: 13, height: 1.45, color: AdminColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: AdminColors.rose)),
          ),
        ],
      ),
    );
    if (ok == true) await controller.removeAdminUser(user.id);
  }
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({
    required this.avatar,
    required this.email,
    required this.detail,
    this.actions,
  });

  final String avatar;
  final String email;
  final String detail;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AdminColors.emerald.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              avatar,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.emerald),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(detail,
                    style: const TextStyle(fontSize: 10.5, color: AdminColors.faint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

class _AddAdminDialog extends StatefulWidget {
  const _AddAdminDialog({required this.controller});

  final AdminController controller;

  @override
  State<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<_AddAdminDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 10) {
      setState(() => _error = 'Password must be at least 10 characters.');
      return;
    }
    final ok = await widget.controller.addAdminUser(email, password);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.controller.manageError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.manageBusy;
        return AlertDialog(
          backgroundColor: AdminColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AdminColors.border),
          ),
          title: const Text('Add admin', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _email,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(hintText: 'Email address'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                    hintText: 'Password (10+ characters)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(fontSize: 12.5, color: AdminColors.rose)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
            ),
            FilledButton(
              onPressed: busy ? null : _add,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Color(0xFF052E22)),
                    )
                  : const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class _ResetAdminDialog extends StatefulWidget {
  const _ResetAdminDialog({required this.controller, required this.user});

  final AdminController controller;
  final AdminUser user;

  @override
  State<_ResetAdminDialog> createState() => _ResetAdminDialogState();
}

class _ResetAdminDialogState extends State<_ResetAdminDialog> {
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_password.text.length < 10) {
      setState(() => _error = 'New password must be at least 10 characters.');
      return;
    }
    final ok = await widget.controller.resetAdminPassword(
        widget.user.id, _password.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdminColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AdminColors.border),
          ),
          content: Text(
            'Password reset for ${widget.user.email}. Their sessions were revoked.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    } else {
      setState(() => _error = widget.controller.manageError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.manageBusy;
        return AlertDialog(
          backgroundColor: AdminColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AdminColors.border),
          ),
          title: Text('Reset password', style: const TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set a new password for ${widget.user.email}. Every session '
                'of theirs is revoked — they sign in with the new password.',
                style: const TextStyle(
                    fontSize: 12.5, height: 1.45, color: AdminColors.muted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                    hintText: 'New password (10+ characters)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(fontSize: 12.5, color: AdminColors.rose)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
            ),
            FilledButton(
              onPressed: busy ? null : _reset,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Color(0xFF052E22)),
                    )
                  : const Text('Reset'),
            ),
          ],
        );
      },
    );
  }
}

// ── audit trail ──────────────────────────────────────────────────────────────

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.entries});

  final List<AuditEntry>? entries;

  static const _actionIcons = {
    'login': Icons.login_rounded,
    'settings_updated': Icons.tune_rounded,
    'admin_created': Icons.person_add_alt_rounded,
    'admin_password_reset': Icons.key_rounded,
    'admin_removed': Icons.person_remove_alt_1_rounded,
    'announcement_created': Icons.campaign_rounded,
    'announcement_deleted': Icons.campaign_outlined,
    'account_suspended': Icons.block_rounded,
    'account_unsuspended': Icons.check_circle_outline_rounded,
    'account_deleted': Icons.delete_forever_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final list = entries;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              icon: Icons.receipt_long_rounded,
              title: 'Audit trail',
              subtitle: 'Every management action, newest first (server keeps 150)',
            ),
            const SizedBox(height: 10),
            if (list == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AdminColors.emerald),
                  ),
                ),
              )
            else if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing recorded yet — actions land here as soon as they '
                  'happen.',
                  style: TextStyle(fontSize: 12.5, color: AdminColors.faint),
                ),
              )
            else
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _actionIcons[e.action] ?? Icons.chevron_right_rounded,
                        size: 15,
                        color: e.action == 'account_deleted'
                            ? AdminColors.rose
                            : e.action == 'account_suspended'
                                ? AdminColors.amber
                                : AdminColors.faint,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _prettyAction(e.action),
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  if ((e.target ?? '').isNotEmpty)
                                    TextSpan(
                                      text: ' · ${e.target}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AdminColors.emerald),
                                    ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.actor} · ${timeAgo(e.t)}'
                              '${(e.detail ?? '').isNotEmpty ? ' · ${e.detail}' : ''}',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  height: 1.4,
                                  color: AdminColors.faint),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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

  String _prettyAction(String action) => switch (action) {
        'login' => 'Signed in',
        'settings_updated' => 'Service settings updated',
        'admin_created' => 'Admin added',
        'admin_password_reset' => 'Admin password reset',
        'admin_removed' => 'Admin removed',
        'announcement_created' => 'Announcement posted',
        'announcement_deleted' => 'Announcement deleted',
        'account_suspended' => 'Account suspended',
        'account_unsuspended' => 'Account unsuspended',
        'account_deleted' => 'Account deleted',
        _ => action,
      };
}
