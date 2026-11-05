import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'card_notification_service.dart';

const _leagues = ['Premier League', 'La Liga', 'Serie A', 'Champions League'];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.profile,
    required this.onLogin,
    required this.onLogout,
    required this.onProfileUpdated,
    required this.onDarkModeChanged,
    super.key,
  });

  final Map<String, dynamic>? profile;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final ValueChanged<Map<String, dynamic>> onProfileUpdated;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _redCards = true;
  bool _redCardAlarm = true;
  bool _goals = true;
  bool _favoriteLeagues = true;
  bool _darkMode = true;
  String _language = 'English';
  Set<String> _selectedLeagues = _leagues.toSet();

  Map<String, dynamic> get _user =>
      _asMap(widget.profile?['user']) ?? const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _restorePreferences();
  }

  Future<void> _restorePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _redCards = prefs.getBool('alert_red_cards') ?? true;
      _redCardAlarm = prefs.getBool('alarm_red_cards') ?? true;
      _goals = prefs.getBool('alert_goals') ?? true;
      _favoriteLeagues = prefs.getBool('alert_favorite_leagues') ?? true;
      _darkMode = prefs.getBool('dark_mode') ?? true;
      _language = prefs.getString('language') ?? 'English';
      _selectedLeagues =
          (prefs.getStringList('preferred_leagues') ?? _leagues).toSet();
    });
    widget.onDarkModeChanged(_darkMode);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _editProfile() async {
    final nameController =
        TextEditingController(text: '${_user['name'] ?? ''}');
    final emailController =
        TextEditingController(text: '${_user['email'] ?? ''}');
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, [
              nameController.text.trim(),
              emailController.text.trim(),
            ]),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    emailController.dispose();
    if (values == null || values.first.isEmpty || !values.last.contains('@')) {
      return;
    }
    final result = await ApiService.updateProfile(
      name: values.first,
      email: values.last,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      widget.onProfileUpdated({
        ...?widget.profile,
        'user': result['user'],
      });
    } else {
      _showMessage('${result['message'] ?? 'Could not update profile.'}');
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              [current.text, next.text],
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    current.dispose();
    next.dispose();
    if (values == null || values[1].length < 8) return;
    final result = await ApiService.updatePassword(
      currentPassword: values[0],
      password: values[1],
    );
    if (!mounted) return;
    _showMessage(result['success'] == true
        ? 'Password updated.'
        : '${result['message'] ?? 'Could not update password.'}');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deviceToken = widget.profile?['device_token'] as String?;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.paddingOf(context).top + 24,
        18,
        110,
      ),
      children: [
        Text(
          'YOUR ACCOUNT',
          style: TextStyle(
            color: scheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const Text(
          'Your dashboard',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        Text(
          'Your account and match preferences.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        _heading(context, 'Profile'),
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: scheme.outline),
            borderRadius: BorderRadius.circular(16),
          ),
          child: widget.profile == null
              ? ListTile(
                  leading: const _SettingsIcon(Icons.person_outline),
                  title: const Text('Sign in to view your profile'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onLogin,
                )
              : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const _SettingsIcon(Icons.person_outline),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_user['name'] ?? 'OddFlip member'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '${_user['email'] ?? ''}',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _ProfileDetail(
                        label: 'FCM device token',
                        value: deviceToken ?? 'Not registered on this device',
                        icon: Icons.notifications_active_outlined,
                      ),
                      const SizedBox(height: 12),
                      _ProfileDetail(
                        label: 'Access',
                        value: 'All features free',
                        icon: Icons.workspace_premium_outlined,
                      ),
                    ],
                  ),
                ),
        ),
        _heading(context, 'Free access'),
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: scheme.outline),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Every feature, for everyone',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Live matches, red-card alerts and match insights are available without a subscription.',
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        _heading(context, 'Notifications'),
        _SettingsCard(children: [
          SwitchListTile(
            secondary: const _SettingsIcon(Icons.notifications_active_outlined),
            title: const Text('Red card notifications'),
            subtitle: const Text('Show a notification when a red card occurs'),
            value: _redCards,
            onChanged: (value) async {
              setState(() => _redCards = value);
              await _saveBool('alert_red_cards', value);
              if (value) await CardNotificationService.requestPermission();
            },
          ),
          SwitchListTile(
            secondary: const _SettingsIcon(Icons.alarm),
            title: const Text('Red card alarm'),
            subtitle: const Text('Play an alert sound when a red card occurs'),
            value: _redCardAlarm,
            onChanged: (value) async {
              setState(() => _redCardAlarm = value);
              await _saveBool('alarm_red_cards', value);
            },
          ),
          SwitchListTile(
            secondary: const _SettingsIcon(Icons.sports_soccer_outlined),
            title: const Text('Goal alerts'),
            value: _goals,
            onChanged: (value) {
              setState(() => _goals = value);
              _saveBool('alert_goals', value);
            },
          ),
          SwitchListTile(
            secondary: const _SettingsIcon(Icons.star_outline),
            title: const Text('Favorite league alerts'),
            value: _favoriteLeagues,
            onChanged: (value) {
              setState(() => _favoriteLeagues = value);
              _saveBool('alert_favorite_leagues', value);
            },
          ),
        ]),
        _heading(context, 'Preferred leagues'),
        Wrap(
          spacing: 7,
          runSpacing: 2,
          children: _leagues.map((league) {
            final selected = _selectedLeagues.contains(league);
            return FilterChip(
              label: Text(league),
              selected: selected,
              onSelected: (value) async {
                setState(() {
                  if (value) {
                    _selectedLeagues.add(league);
                  } else {
                    _selectedLeagues.remove(league);
                  }
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setStringList(
                  'preferred_leagues',
                  _selectedLeagues.toList(),
                );
              },
            );
          }).toList(),
        ),
        _heading(context, 'Account & security'),
        _SettingsCard(children: [
          ListTile(
            leading: const _SettingsIcon(Icons.edit_outlined),
            title: const Text('Edit profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.profile == null ? widget.onLogin : _editProfile,
          ),
          ListTile(
            leading: const _SettingsIcon(Icons.lock_outline),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.profile == null ? widget.onLogin : _changePassword,
          ),
        ]),
        _heading(context, 'App preferences'),
        _SettingsCard(children: [
          SwitchListTile(
            secondary: const _SettingsIcon(Icons.dark_mode_outlined),
            title: Text(_darkMode ? 'Dark mode' : 'Light mode'),
            subtitle: const Text('Choose the app appearance'),
            value: _darkMode,
            onChanged: (value) async {
              setState(() => _darkMode = value);
              widget.onDarkModeChanged(value);
              await _saveBool('dark_mode', value);
            },
          ),
          ListTile(
            leading: const _SettingsIcon(Icons.language_outlined),
            title: const Text('Language'),
            trailing: DropdownButton<String>(
              value: _language,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'English', child: Text('English')),
                DropdownMenuItem(value: 'Kiswahili', child: Text('Kiswahili')),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _language = value);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('language', value);
              },
            ),
          ),
        ]),
        if (widget.profile != null)
          TextButton.icon(
            onPressed: widget.onLogout,
            icon: Icon(Icons.logout, color: scheme.primary),
            label: Text('Log out', style: TextStyle(color: scheme.primary)),
          ),
      ],
    );
  }

  Widget _heading(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: children),
      );
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(icon, size: 20),
      );
}
