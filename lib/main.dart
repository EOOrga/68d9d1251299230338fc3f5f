import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String appName = 'DONATO VALERIE';
const String _storageKey = 'donato_valerie_operations_v1';
const bool kScreenshotMode = bool.fromEnvironment('SCREENSHOT_MODE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await OperationsStore.load(screenshotMode: kScreenshotMode);
  runApp(DonatoValerieApp(store: store));
}

class DonatoValerieApp extends StatelessWidget {
  const DonatoValerieApp({super.key, required this.store});

  final OperationsStore store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF9E7A35);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: const Color(0xFF0A2742),
      secondary: const Color(0xFF9E7A35),
      tertiary: const Color(0xFF1E7668),
      surface: const Color(0xFFFAF8F2),
    );

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFFBFAF6),
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE3DFD5)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: const Color(0xFFEAD8A2),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: HomeShell(store: store),
    );
  }
}

enum RecordKind { interview, equipment, shift, compliance }

extension RecordKindDetails on RecordKind {
  String get label => switch (this) {
    RecordKind.interview => 'Interview',
    RecordKind.equipment => 'Equipment',
    RecordKind.shift => 'Shift',
    RecordKind.compliance => 'Compliance',
  };

  IconData get icon => switch (this) {
    RecordKind.interview => Icons.badge_outlined,
    RecordKind.equipment => Icons.inventory_2_outlined,
    RecordKind.shift => Icons.calendar_month_outlined,
    RecordKind.compliance => Icons.fact_check_outlined,
  };
}

class OperationRecord {
  const OperationRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.owner,
    required this.schedule,
    required this.status,
    required this.notes,
    required this.secondary,
  });

  final String id;
  final RecordKind kind;
  final String title;
  final String subtitle;
  final String owner;
  final String schedule;
  final String status;
  final String notes;
  final String secondary;

  OperationRecord copyWith({String? status}) {
    return OperationRecord(
      id: id,
      kind: kind,
      title: title,
      subtitle: subtitle,
      owner: owner,
      schedule: schedule,
      status: status ?? this.status,
      notes: notes,
      secondary: secondary,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'subtitle': subtitle,
    'owner': owner,
    'schedule': schedule,
    'status': status,
    'notes': notes,
    'secondary': secondary,
  };

  static OperationRecord fromJson(Map<String, Object?> json) {
    return OperationRecord(
      id: json['id'] as String? ?? _newId(),
      kind: RecordKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => RecordKind.interview,
      ),
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      schedule: json['schedule'] as String? ?? '',
      status: json['status'] as String? ?? 'Planned',
      notes: json['notes'] as String? ?? '',
      secondary: json['secondary'] as String? ?? '',
    );
  }
}

class OperationsStore extends ChangeNotifier {
  OperationsStore._({
    required List<OperationRecord> records,
    required this.screenshotMode,
    SharedPreferences? preferences,
  }) : _records = records,
       _preferences = preferences;

  final bool screenshotMode;
  final SharedPreferences? _preferences;
  List<OperationRecord> _records;

  static Future<OperationsStore> load({bool screenshotMode = false}) async {
    if (screenshotMode) {
      return OperationsStore._(records: _sampleRecords(), screenshotMode: true);
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return OperationsStore._(
        records: _starterRecords(),
        screenshotMode: false,
        preferences: prefs,
      );
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final records = decoded
          .whereType<Map>()
          .map(
            (item) => OperationRecord.fromJson(Map<String, Object?>.from(item)),
          )
          .toList();
      return OperationsStore._(
        records: records,
        screenshotMode: false,
        preferences: prefs,
      );
    } on FormatException {
      return OperationsStore._(
        records: _starterRecords(),
        screenshotMode: false,
        preferences: prefs,
      );
    }
  }

  List<OperationRecord> get records => List.unmodifiable(_records);

  List<OperationRecord> byKind(RecordKind kind) {
    return _records.where((record) => record.kind == kind).toList();
  }

  int count(RecordKind kind) => byKind(kind).length;

  int get activeEquipment => byKind(
    RecordKind.equipment,
  ).where((record) => record.status != 'Returned').length;

  int get openCompliance => byKind(
    RecordKind.compliance,
  ).where((record) => record.status != 'Closed').length;

  List<OperationRecord> get priorities {
    return _records
        .where((record) => record.status == 'Ready' || record.status == 'Open')
        .take(4)
        .toList();
  }

  Future<void> add(OperationRecord record) async {
    _records = [record, ..._records];
    notifyListeners();
    await _save();
  }

  Future<void> updateStatus(String id, String status) async {
    _records = [
      for (final record in _records)
        if (record.id == id) record.copyWith(status: status) else record,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> clearLocalRecords() async {
    _records = [];
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    if (screenshotMode) {
      return;
    }
    final data = jsonEncode(_records.map((record) => record.toJson()).toList());
    await _preferences?.setString(_storageKey, data);
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final OperationsStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  String get _title => switch (_selectedIndex) {
    0 => appName,
    1 => 'Schedule',
    2 => 'Equipment',
    3 => 'Compliance',
    _ => 'Settings',
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final pages = [
          OverviewPage(store: widget.store),
          SchedulePage(store: widget.store),
          EquipmentPage(store: widget.store),
          CompliancePage(store: widget.store),
          SettingsPage(store: widget.store),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(_title),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    widget.store.screenshotMode ? 'SCREENSHOT' : 'LOCAL',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(child: pages[_selectedIndex]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Overview',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                selectedIcon: Icon(Icons.event_note),
                label: 'Schedule',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: 'Gear',
              ),
              NavigationDestination(
                icon: Icon(Icons.fact_check_outlined),
                selectedIcon: Icon(Icons.fact_check),
                label: 'Reports',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.store});

  final OperationsStore store;

  @override
  Widget build(BuildContext context) {
    final priorities = store.priorities;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const BrandPanel(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            StatTile(
              label: 'Interviews',
              value: store.count(RecordKind.interview).toString(),
              icon: Icons.badge_outlined,
            ),
            StatTile(
              label: 'Active gear',
              value: store.activeEquipment.toString(),
              icon: Icons.inventory_2_outlined,
            ),
            StatTile(
              label: 'Shifts',
              value: store.count(RecordKind.shift).toString(),
              icon: Icons.calendar_month_outlined,
            ),
            StatTile(
              label: 'Open reports',
              value: store.openCompliance.toString(),
              icon: Icons.fact_check_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionTitle(
          title: 'Priority board',
          actionText: '${priorities.length} active',
        ),
        if (priorities.isEmpty)
          const EmptyState(message: 'No active priorities saved yet.')
        else
          ...priorities.map((record) => RecordListTile(record: record)),
        const SizedBox(height: 16),
        SectionTitle(title: 'Operating cadence', actionText: 'Today'),
        const CadenceCard(),
      ],
    );
  }
}

class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF071428),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(8),
              image: const DecorationImage(
                image: AssetImage('docs/icon.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operations desk',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFEAD8A2),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Coordinate interviews, equipment, shifts, and compliance from one local workspace.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 42) / 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key, required this.store});

  final OperationsStore store;

  @override
  Widget build(BuildContext context) {
    final interviews = store.byKind(RecordKind.interview);
    final shifts = store.byKind(RecordKind.shift);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openForm(context, RecordKind.interview),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Interview'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openForm(context, RecordKind.shift),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Shift'),
                  ),
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Interviews'),
              Tab(text: 'Shifts'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                RecordsList(
                  records: interviews,
                  empty: 'No interview holds saved.',
                  onTap: (record) => _openDetail(context, record),
                ),
                RecordsList(
                  records: shifts,
                  empty: 'No shift coverage saved.',
                  onTap: (record) => _openDetail(context, record),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, RecordKind kind) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordFormPage(store: store, kind: kind),
      ),
    );
  }

  void _openDetail(BuildContext context, OperationRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordDetailPage(store: store, record: record),
      ),
    );
  }
}

class EquipmentPage extends StatelessWidget {
  const EquipmentPage({super.key, required this.store});

  final OperationsStore store;

  @override
  Widget build(BuildContext context) {
    final equipment = store.byKind(RecordKind.equipment);
    return Scaffold(
      body: RecordsList(
        records: equipment,
        empty: 'No equipment checkouts saved.',
        onTap: (record) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecordDetailPage(store: store, record: record),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                RecordFormPage(store: store, kind: RecordKind.equipment),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Checkout'),
      ),
    );
  }
}

class CompliancePage extends StatelessWidget {
  const CompliancePage({super.key, required this.store});

  final OperationsStore store;

  @override
  Widget build(BuildContext context) {
    final reports = store.byKind(RecordKind.compliance);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          SectionTitle(
            title: 'Compliance reporting',
            actionText: '${reports.length} saved',
          ),
          const ComplianceSummary(),
          const SizedBox(height: 12),
          if (reports.isEmpty)
            const EmptyState(message: 'No compliance reports saved.')
          else
            ...reports.map(
              (record) => RecordListTile(
                record: record,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RecordDetailPage(store: store, record: record),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                RecordFormPage(store: store, kind: RecordKind.compliance),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Report'),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});

  final OperationsStore store;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SectionTitle(title: 'Workspace', actionText: 'Private'),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.business_outlined),
                title: Text(appName),
                subtitle: Text('Business operations workspace'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Local storage'),
                subtitle: Text(
                  store.screenshotMode
                      ? 'Screenshot data is temporary and not saved.'
                      : 'Records are saved on this device only.',
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.privacy_tip_outlined),
                title: Text('Privacy posture'),
                subtitle: Text('No account, no cloud sync, no analytics.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: store.screenshotMode
              ? null
              : () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Clear local records?'),
                      content: const Text(
                        'This removes saved operations records from this device.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await store.clearLocalRecords();
                  }
                },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear Local Records'),
        ),
      ],
    );
  }
}

class RecordsList extends StatelessWidget {
  const RecordsList({
    super.key,
    required this.records,
    required this.empty,
    this.onTap,
  });

  final List<OperationRecord> records;
  final String empty;
  final ValueChanged<OperationRecord>? onTap;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [EmptyState(message: empty)],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final record = records[index];
        return RecordListTile(record: record, onTap: () => onTap?.call(record));
      },
    );
  }
}

class RecordListTile extends StatelessWidget {
  const RecordListTile({super.key, required this.record, this.onTap});

  final OperationRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _statusColor(record.status).withValues(alpha: 0.16),
          child: Icon(record.kind.icon, color: _statusColor(record.status)),
        ),
        title: Text(
          record.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${record.schedule}  |  ${record.owner}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        trailing: StatusChip(status: record.status),
      ),
    );
  }
}

class RecordDetailPage extends StatelessWidget {
  const RecordDetailPage({
    super.key,
    required this.store,
    required this.record,
  });

  final OperationsStore store;
  final OperationRecord record;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final latest = store.records.firstWhere(
          (item) => item.id == record.id,
          orElse: () => record,
        );
        return Scaffold(
          appBar: AppBar(title: Text(latest.kind.label)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(latest.kind.icon, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              latest.title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StatusChip(status: latest.status),
                      const SizedBox(height: 18),
                      DetailRow(label: 'Focus', value: latest.subtitle),
                      DetailRow(label: 'Owner', value: latest.owner),
                      DetailRow(label: 'Timing', value: latest.schedule),
                      DetailRow(label: 'Extra', value: latest.secondary),
                      DetailRow(label: 'Notes', value: latest.notes),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await store.updateStatus(latest.id, _completedStatus(latest));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${latest.kind.label} updated')),
                    );
                  }
                },
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_actionLabel(latest)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class RecordFormPage extends StatefulWidget {
  const RecordFormPage({super.key, required this.store, required this.kind});

  final OperationsStore store;
  final RecordKind kind;

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _owner;
  late final TextEditingController _schedule;
  late final TextEditingController _secondary;
  late final TextEditingController _notes;
  late String _status;

  @override
  void initState() {
    super.initState();
    final defaults = _formDefaults(widget.kind);
    _title = TextEditingController(text: defaults.title);
    _subtitle = TextEditingController(text: defaults.subtitle);
    _owner = TextEditingController(text: defaults.owner);
    _schedule = TextEditingController(text: defaults.schedule);
    _secondary = TextEditingController(text: defaults.secondary);
    _notes = TextEditingController(text: defaults.notes);
    _status = defaults.status;
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _owner.dispose();
    _schedule.dispose();
    _secondary.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return Scaffold(
      appBar: AppBar(title: Text('New ${kind.label}')),
      body: Form(
        key: _formKey,
        child: ListView(
          key: const ValueKey('recordFormList'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              _formIntro(kind),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: _titleLabel(kind)),
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _subtitle,
              decoration: InputDecoration(labelText: _subtitleLabel(kind)),
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _owner,
              decoration: const InputDecoration(labelText: 'Owner'),
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _schedule,
              decoration: const InputDecoration(labelText: 'Timing'),
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _secondary,
              decoration: InputDecoration(labelText: _secondaryLabel(kind)),
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: _statusOptions(kind)
                  .map(
                    (status) =>
                        DropdownMenuItem(value: status, child: Text(status)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _status = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              minLines: 3,
              maxLines: 5,
              validator: _required,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Record'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    await widget.store.add(
      OperationRecord(
        id: _newId(),
        kind: widget.kind,
        title: _title.text.trim(),
        subtitle: _subtitle.text.trim(),
        owner: _owner.text.trim(),
        schedule: _schedule.text.trim(),
        status: _status,
        secondary: _secondary.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.actionText,
  });

  final String title;
  final String actionText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            actionText,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      constraints: const BoxConstraints(minWidth: 76),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(value),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class CadenceCard extends StatelessWidget {
  const CadenceCard({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('08:30', 'Review interview confirmations'),
      ('10:00', 'Audit open equipment checkouts'),
      ('14:00', 'Publish shift coverage notes'),
      ('16:30', 'Close compliance exceptions'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 54,
                      child: Text(
                        item.$1,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(child: Text(item.$2)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ComplianceSummary extends StatelessWidget {
  const ComplianceSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircularProgressIndicator(
              value: 0.72,
              strokeWidth: 8,
              backgroundColor: colors.secondary.withValues(alpha: 0.18),
              color: const Color(0xFF1E7668),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '72% cleared',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text('Open findings are grouped by owner and due date.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

OperationRecord _formDefaults(RecordKind kind) {
  if (!kScreenshotMode) {
    return OperationRecord(
      id: _newId(),
      kind: kind,
      title: '',
      subtitle: '',
      owner: '',
      schedule: '',
      status: _statusOptions(kind).first,
      secondary: '',
      notes: '',
    );
  }

  return switch (kind) {
    RecordKind.interview => OperationRecord(
      id: _newId(),
      kind: kind,
      title: 'Noah Marceau',
      subtitle: 'Operations analyst',
      owner: 'Valerie desk',
      schedule: 'Thu 11:30',
      status: 'Ready',
      secondary: 'Panel B',
      notes: 'Prepare role scorecard and equipment access review.',
    ),
    RecordKind.equipment => OperationRecord(
      id: _newId(),
      kind: kind,
      title: 'Tablet kit DV-18',
      subtitle: 'Assigned to field audit team',
      owner: 'Rina Patel',
      schedule: 'Return Fri 17:00',
      status: 'Checked out',
      secondary: 'Good condition',
      notes: 'Includes scanner, charger, and sealed compliance forms.',
    ),
    RecordKind.shift => OperationRecord(
      id: _newId(),
      kind: kind,
      title: 'Evening dispatch',
      subtitle: 'Warehouse coverage',
      owner: 'Mateo Ruiz',
      schedule: 'Fri 18:00-02:00',
      status: 'Open',
      secondary: 'One backup needed',
      notes: 'Confirm forklift certified backup before 15:00.',
    ),
    RecordKind.compliance => OperationRecord(
      id: _newId(),
      kind: kind,
      title: 'Safety binder review',
      subtitle: 'Floor 3 receiving',
      owner: 'Amal Green',
      schedule: 'Due today',
      status: 'Open',
      secondary: 'Medium severity',
      notes: 'Missing acknowledgement sheet for weekend crew.',
    ),
  };
}

List<OperationRecord> _starterRecords() => [
  const OperationRecord(
    id: 'starter-interview',
    kind: RecordKind.interview,
    title: 'Candidate intake queue',
    subtitle: 'Front desk supervisor',
    owner: 'Hiring desk',
    schedule: 'Today 09:30',
    status: 'Ready',
    secondary: 'Panel A',
    notes: 'Use this starter record as a model for local interview planning.',
  ),
  const OperationRecord(
    id: 'starter-equipment',
    kind: RecordKind.equipment,
    title: 'Laptop pool checkout',
    subtitle: 'Temporary analyst station',
    owner: 'Operations desk',
    schedule: 'Return Friday',
    status: 'Checked out',
    secondary: 'Asset tag DV-02',
    notes: 'Track equipment locally until it is returned.',
  ),
  const OperationRecord(
    id: 'starter-compliance',
    kind: RecordKind.compliance,
    title: 'Daily floor checklist',
    subtitle: 'Receiving zone',
    owner: 'Compliance lead',
    schedule: 'Due today',
    status: 'Open',
    secondary: 'Low severity',
    notes: 'Record exceptions and close them after verification.',
  ),
];

List<OperationRecord> _sampleRecords() => [
  const OperationRecord(
    id: 'int-1',
    kind: RecordKind.interview,
    title: 'Maya Laurent',
    subtitle: 'Shift coordinator interview',
    owner: 'Rina Patel',
    schedule: 'Today 09:45',
    status: 'Ready',
    secondary: 'Room 2, panel A',
    notes: 'Bring structured scorecard and verify weekend availability.',
  ),
  const OperationRecord(
    id: 'int-2',
    kind: RecordKind.interview,
    title: 'Owen Clarke',
    subtitle: 'Equipment clerk interview',
    owner: 'Mateo Ruiz',
    schedule: 'Today 13:20',
    status: 'Planned',
    secondary: 'Video room',
    notes: 'Ask about inventory reconciliation and handoff routines.',
  ),
  const OperationRecord(
    id: 'eq-1',
    kind: RecordKind.equipment,
    title: 'Scanner set DV-24',
    subtitle: 'Assigned to receiving audit',
    owner: 'Amal Green',
    schedule: 'Return Thu 18:00',
    status: 'Checked out',
    secondary: 'Battery verified',
    notes: 'Includes scanner, dock, charger, and two seal rolls.',
  ),
  const OperationRecord(
    id: 'eq-2',
    kind: RecordKind.equipment,
    title: 'Laptop DV-09',
    subtitle: 'Interview panel station',
    owner: 'Noah Kim',
    schedule: 'Return today',
    status: 'Ready',
    secondary: 'Clean image',
    notes: 'Loaded with interview scorecard templates for local use.',
  ),
  const OperationRecord(
    id: 'shift-1',
    kind: RecordKind.shift,
    title: 'Evening receiving',
    subtitle: 'Dock team coverage',
    owner: 'Rina Patel',
    schedule: 'Today 18:00-02:00',
    status: 'Open',
    secondary: 'Needs one backup',
    notes: 'Coverage gap if compliance report review runs late.',
  ),
  const OperationRecord(
    id: 'shift-2',
    kind: RecordKind.shift,
    title: 'Morning dispatch',
    subtitle: 'Customer priority lane',
    owner: 'Mateo Ruiz',
    schedule: 'Wed 06:00-14:00',
    status: 'Covered',
    secondary: 'Four staff confirmed',
    notes: 'Keep one flex worker available for returns.',
  ),
  const OperationRecord(
    id: 'comp-1',
    kind: RecordKind.compliance,
    title: 'PPE station exception',
    subtitle: 'Receiving dock',
    owner: 'Amal Green',
    schedule: 'Due today',
    status: 'Open',
    secondary: 'Medium severity',
    notes: 'Face shield count is below minimum. Recheck after resupply.',
  ),
  const OperationRecord(
    id: 'comp-2',
    kind: RecordKind.compliance,
    title: 'Training log review',
    subtitle: 'Weekend crew',
    owner: 'Noah Kim',
    schedule: 'Due Friday',
    status: 'Ready',
    secondary: 'Two acknowledgements pending',
    notes: 'Collect signatures after shift briefing.',
  ),
];

List<String> _statusOptions(RecordKind kind) => switch (kind) {
  RecordKind.interview => ['Ready', 'Planned', 'Confirmed'],
  RecordKind.equipment => ['Ready', 'Checked out', 'Returned'],
  RecordKind.shift => ['Open', 'Covered', 'Closed'],
  RecordKind.compliance => ['Open', 'Ready', 'Closed'],
};

String _titleLabel(RecordKind kind) => switch (kind) {
  RecordKind.interview => 'Candidate',
  RecordKind.equipment => 'Asset',
  RecordKind.shift => 'Shift name',
  RecordKind.compliance => 'Report title',
};

String _subtitleLabel(RecordKind kind) => switch (kind) {
  RecordKind.interview => 'Role',
  RecordKind.equipment => 'Assignee',
  RecordKind.shift => 'Coverage area',
  RecordKind.compliance => 'Area',
};

String _secondaryLabel(RecordKind kind) => switch (kind) {
  RecordKind.interview => 'Room or panel',
  RecordKind.equipment => 'Condition',
  RecordKind.shift => 'Coverage note',
  RecordKind.compliance => 'Severity',
};

String _formIntro(RecordKind kind) => switch (kind) {
  RecordKind.interview => 'Schedule an interview hold and assign an owner.',
  RecordKind.equipment =>
    'Log an equipment checkout before it leaves the desk.',
  RecordKind.shift => 'Add a shift coverage item for the operations board.',
  RecordKind.compliance => 'Capture a compliance finding and due owner.',
};

String _actionLabel(OperationRecord record) => switch (record.kind) {
  RecordKind.interview => 'Mark Confirmed',
  RecordKind.equipment => 'Mark Returned',
  RecordKind.shift => 'Mark Covered',
  RecordKind.compliance => 'Close Report',
};

String _completedStatus(OperationRecord record) => switch (record.kind) {
  RecordKind.interview => 'Confirmed',
  RecordKind.equipment => 'Returned',
  RecordKind.shift => 'Covered',
  RecordKind.compliance => 'Closed',
};

Color _statusColor(String status) => switch (status) {
  'Open' => const Color(0xFFB8462F),
  'Ready' => const Color(0xFF1E7668),
  'Planned' => const Color(0xFF9E7A35),
  'Checked out' => const Color(0xFF0A5692),
  'Covered' => const Color(0xFF1E7668),
  'Confirmed' => const Color(0xFF1E7668),
  'Returned' => const Color(0xFF55524B),
  'Closed' => const Color(0xFF55524B),
  _ => const Color(0xFF0A2742),
};

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
