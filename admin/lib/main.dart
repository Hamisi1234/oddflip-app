import 'package:flutter/material.dart';

import 'admin_api.dart';

void main() => runApp(const OddFlipAdminApp());

const _navy = Color(0xFF0B1220);
const _card = Color(0xFF151F30);
const _red = Color(0xFFF04452);
const _muted = Color(0xFF9AA8BA);
const _green = Color(0xFF3DC98A);

class OddFlipAdminApp extends StatelessWidget {
  const OddFlipAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OddFlip Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _navy,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _red,
            brightness: Brightness.dark,
            surface: _card,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
          ),
        ),
        home: const AdminGate(),
      );
}

class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  final _api = AdminApi();
  bool _checking = true;
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final token = await _api.readToken();
      if (token != null && token.isNotEmpty) {
        _user = await _api.currentUser();
      }
    } on AdminApiException {
      _user = null;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_user == null) {
      return LoginScreen(
        api: _api,
        onLogin: (user) => setState(() => _user = user),
      );
    }
    return AdminDashboard(
      api: _api,
      user: _user!,
      onLogout: () => setState(() => _user = null),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.api, required this.onLogin, super.key});

  final AdminApi api;
  final ValueChanged<Map<String, dynamic>> onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await widget.api.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted) widget.onLogin(user);
    } on AdminApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                color: _card,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.sports_soccer, color: _red, size: 46),
                        const SizedBox(height: 14),
                        Text(
                          'OddFlip Admin',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ingia kwa akaunti yenye ruhusa ya admin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Barua pepe',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) =>
                              value == null || !value.trim().contains('@')
                                  ? 'Weka barua pepe sahihi.'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          decoration: InputDecoration(
                            labelText: 'Nenosiri',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Weka nenosiri.'
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(color: Color(0xFFFF7B83)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: _red,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Ingia'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({
    required this.api,
    required this.user,
    required this.onLogout,
    super.key,
  });

  final AdminApi api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _search = TextEditingController();
  AdminStats? _stats;
  AdminUserPage? _userPage;
  String? _statusFilter;
  String? _error;
  int _page = 1;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.fetchStats(),
        widget.api.fetchUsers(
          page: _page,
          search: _search.text,
          status: _statusFilter,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as AdminStats;
        _userPage = results[1] as AdminUserPage;
        _page = _userPage!.currentPage;
      });
    } on AdminApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } on AdminApiException catch (error) {
      _showMessage(error.message);
    } finally {
      widget.onLogout();
    }
  }

  Future<void> _changeStatus(AdminUser user) async {
    if (user.status == 'active_paid' || user.status == 'active') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Zima subscription?'),
          content: Text('Subscription ya ${user.name} itazimwa.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ghairi'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: _red),
              child: const Text('Zima'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _saveStatus(user, 'disabled');
      return;
    }

    final fields = await showDialog<_ActivationDetails>(
      context: context,
      builder: (context) => const _ActivationDialog(),
    );
    if (fields == null) return;
    await _saveStatus(
      user,
      'active_paid',
      reference: fields.reference,
      paymentMethod: fields.paymentMethod,
    );
  }

  Future<void> _saveStatus(
    AdminUser user,
    String status, {
    String? reference,
    String? paymentMethod,
  }) async {
    setState(() => _busy = true);
    try {
      await widget.api.setStatus(
        userId: user.id,
        status: status,
        reference: reference,
        paymentMethod: paymentMethod,
      );
      _showMessage(
        status == 'active_paid'
            ? 'Subscription imewashwa kwa ${user.name}.'
            : 'Subscription ya ${user.name} imezimwa.',
      );
      await _refresh();
    } on AdminApiException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = _userPage?.users ?? const <AdminUser>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('OddFlip Admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Akaunti',
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(widget.user['email']?.toString() ?? 'Admin'),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Toka'),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading && _stats == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                  children: [
                    Text(
                      'Karibu, ${widget.user['name'] ?? 'Admin'}',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Muhtasari wa mapato na usimamizi wa subscriptions.',
                      style: TextStyle(color: _muted),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _error!, onRetry: _refresh),
                    ],
                    const SizedBox(height: 20),
                    _StatsGrid(stats: _stats),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Watumiaji',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${_userPage?.total ?? 0} jumla',
                          style: const TextStyle(color: _muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _UserFilters(
                      searchController: _search,
                      status: _statusFilter,
                      onSearch: () {
                        _page = 1;
                        _refresh();
                      },
                      onStatusChanged: (value) {
                        setState(() {
                          _statusFilter = value;
                          _page = 1;
                        });
                        _refresh();
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_busy) const LinearProgressIndicator(),
                    if (users.isEmpty && !_loading)
                      const _EmptyUsers()
                    else
                      ...users.map(
                        (user) => _UserCard(
                          user: user,
                          busy: _busy,
                          onChangeStatus: () => _changeStatus(user),
                        ),
                      ),
                    _Pagination(
                      currentPage: _userPage?.currentPage ?? 1,
                      lastPage: _userPage?.lastPage ?? 1,
                      onPageChanged: (page) {
                        setState(() => _page = page);
                        _refresh();
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Kabla ya kuwasha paid plan, hakikisha umethibitisha malipo ya TZS 5,000 nje ya app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final AdminStats? stats;

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        'Mapato yanayokadiriwa',
        '${stats?.currency ?? 'TZS'} ${_formatNumber(stats?.totalRevenue ?? 0)}',
        Icons.payments_outlined,
        _green,
      ),
      (
        'Watumiaji wa trial',
        '${stats?.freeTrialUsers ?? 0}',
        Icons.hourglass_bottom_rounded,
        const Color(0xFFFFC45E),
      ),
      (
        'Paid subscriptions',
        '${stats?.activePaidUsers ?? 0}',
        Icons.verified_outlined,
        const Color(0xFF65B9FF),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 900
            ? 3
            : constraints.maxWidth > 560
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: values.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 118,
          ),
          itemBuilder: (context, index) {
            final item = values[index];
            return Card(
              color: _card,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: item.$4.withValues(alpha: 0.14),
                      foregroundColor: item.$4,
                      child: Icon(item.$3),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.$2,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UserFilters extends StatelessWidget {
  const _UserFilters({
    required this.searchController,
    required this.status,
    required this.onSearch,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final String? status;
  final VoidCallback onSearch;
  final ValueChanged<String?> onStatusChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: 'Tafuta jina au barua pepe',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Tafuta',
                onPressed: onSearch,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          );
          final filter = DropdownButtonFormField<String?>(
            initialValue: status,
            decoration: const InputDecoration(
              labelText: 'Status',
              prefixIcon: Icon(Icons.filter_list),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Status zote')),
              DropdownMenuItem(value: 'free_trial', child: Text('Free trial')),
              DropdownMenuItem(
                value: 'active_paid',
                child: Text('Active paid'),
              ),
              DropdownMenuItem(value: 'expired', child: Text('Expired')),
              DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
            ],
            onChanged: onStatusChanged,
          );
          if (constraints.maxWidth > 620) {
            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 12),
                SizedBox(width: 220, child: filter),
              ],
            );
          }
          return Column(
            children: [
              search,
              const SizedBox(height: 10),
              filter,
            ],
          );
        },
      );
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.busy,
    required this.onChangeStatus,
  });

  final AdminUser user;
  final bool busy;
  final VoidCallback onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final active = user.status == 'active_paid' || user.status == 'active';
    final color = switch (user.status) {
      'active_paid' || 'active' => _green,
      'disabled' || 'disabled_by_admin' => _red,
      'expired' => const Color(0xFFFFC45E),
      _ => const Color(0xFF65B9FF),
    };
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final identity = Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.14),
                  foregroundColor: color,
                  child: Text(
                    user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user.email,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final statusAndAction = Column(
              crossAxisAlignment: constraints.maxWidth > 600
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.stretch,
              children: [
                _StatusPill(status: user.status, color: color),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      busy || user.role == 'admin' ? null : onChangeStatus,
                  icon: Icon(
                    active ? Icons.block_outlined : Icons.check_circle_outline,
                    size: 17,
                  ),
                  label: Text(active ? 'Zima access' : 'Washa paid'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: active ? _red : _green,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            );
            if (constraints.maxWidth > 600) {
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 12),
                  statusAndAction,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 12),
                statusAndAction,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status.replaceAll('_', ' ').toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.currentPage,
    required this.lastPage,
    required this.onPageChanged,
  });

  final int currentPage;
  final int lastPage;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed:
                  currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('$currentPage / $lastPage'),
            IconButton(
              onPressed: currentPage < lastPage
                  ? () => onPageChanged(currentPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF3C2028),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Color(0xFFFF7B83)),
          title: Text(message),
          trailing: IconButton(
            tooltip: 'Jaribu tena',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
}

class _EmptyUsers extends StatelessWidget {
  const _EmptyUsers();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          children: [
            Icon(Icons.person_search_outlined, size: 36, color: _muted),
            SizedBox(height: 8),
            Text('Hakuna watumiaji waliopatikana.'),
          ],
        ),
      );
}

class _ActivationDetails {
  const _ActivationDetails(this.reference, this.paymentMethod);

  final String reference;
  final String paymentMethod;
}

class _ActivationDialog extends StatefulWidget {
  const _ActivationDialog();

  @override
  State<_ActivationDialog> createState() => _ActivationDialogState();
}

class _ActivationDialogState extends State<_ActivationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  String _method = 'mobile_money';

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Washa paid subscription'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Thibitisha kwanza malipo ya TZS 5,000. Reference lazima iwe ya kipekee.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reference,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Payment reference',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Weka payment reference.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Njia ya malipo'),
                items: const [
                  DropdownMenuItem(
                    value: 'mobile_money',
                    child: Text('Mobile money'),
                  ),
                  DropdownMenuItem(
                    value: 'bank',
                    child: Text('Benki'),
                  ),
                  DropdownMenuItem(
                    value: 'cash',
                    child: Text('Cash'),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Nyingine'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _method = value);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ghairi'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _ActivationDetails(_reference.text.trim(), _method),
              );
            },
            child: const Text('Thibitisha na washa'),
          ),
        ],
      );
}

String _formatNumber(int value) {
  final digits = value.toString();
  final result = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) result.write(',');
    result.write(digits[index]);
  }
  return result.toString();
}
