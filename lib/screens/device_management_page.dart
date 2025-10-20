import 'package:flutter/material.dart';
import '../models/planned_device.dart';
import '../models/device_presets.dart';
import '../services/planned_device_service.dart';
import '../services/premium_service.dart';
import '../services/savings_tips_service.dart';
import '../widgets/premium_dialog.dart';

/// Screen to manage planned devices (add/edit/delete)
class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({Key? key}) : super(key: key);

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  final _deviceService = PlannedDeviceService();
  List<PlannedDevice> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final devices = await _deviceService.getDevices();
    setState(() {
      _devices = devices;
      _isLoading = false;
    });
  }

  Future<void> _addDevice() async {
    // Check if user can add more devices
    final premiumService = PremiumService();
    final hasPremium = await premiumService.hasPremium();

    if (!hasPremium && _devices.length >= PremiumService.freeDeviceLimit) {
      // Show premium dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => PremiumDialog(
            feature: 'Unbegrenzte Geräte: Sie haben das Limit von ${PremiumService.freeDeviceLimit} kostenlosen Geräten erreicht.',
          ),
        );
      }
      return;
    }

    final device = await showDialog<PlannedDevice>(
      context: context,
      builder: (context) => DeviceEditDialog(),
    );

    if (device != null) {
      await _deviceService.saveDevice(device);

      // Invalidate tips cache to force recalculation with new device
      await SavingsTipsService().invalidateCache();

      _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.name} hinzugefügt')),
        );
      }
    }
  }

  Future<void> _editDevice(PlannedDevice device) async {
    final updatedDevice = await showDialog<PlannedDevice>(
      context: context,
      builder: (context) => DeviceEditDialog(device: device),
    );

    if (updatedDevice != null) {
      await _deviceService.saveDevice(updatedDevice);

      // Invalidate tips cache to force recalculation with updated settings
      await SavingsTipsService().invalidateCache();

      _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${updatedDevice.name} aktualisiert')),
        );
      }
    }
  }

  Future<void> _deleteDevice(PlannedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Gerät entfernen?'),
        content: Text('Möchten Sie "${device.name}" wirklich entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Entfernen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deviceService.deleteDevice(device.id);

      // Invalidate tips cache since device was removed
      await SavingsTipsService().invalidateCache();

      _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.name} entfernt')),
        );
      }
    }
  }

  Future<void> _toggleDevice(PlannedDevice device) async {
    final updatedDevice = device.copyWith(isEnabled: !device.isEnabled);
    await _deviceService.saveDevice(updatedDevice);

    // Invalidate tips cache when toggling device on/off
    await SavingsTipsService().invalidateCache();

    _loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Meine Geräte'),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Optimale Zeitfenster'),
                  content: SingleChildScrollView(
                    child: Text(
                      'Fügen Sie Ihre Geräte hinzu, um den günstigsten Zeitpunkt für deren Betrieb zu finden.\n\n'
                      'Sie können optionale Zeitbeschränkungen festlegen (z.B. "nicht vor 6:00 Uhr starten").\n\n'
                      'Die App berechnet automatisch das optimale Zeitfenster basierend auf den aktuellen Strompreisen.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? _buildEmptyState()
              : _buildDeviceList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDevice,
        child: Icon(Icons.add),
        tooltip: 'Gerät hinzufügen',
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.power, size: 80, color: Colors.grey),
            SizedBox(height: 24),
            Text(
              'Noch keine Geräte',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 12),
            Text(
              'Fügen Sie Ihre Geräte hinzu, um den optimalen Zeitpunkt für deren Betrieb zu finden.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _addDevice,
              icon: Icon(Icons.add),
              label: Text('Erstes Gerät hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: device.isEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              child: Icon(device.icon, color: Colors.white),
            ),
            title: Text(
              device.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: device.isEnabled ? null : Colors.grey,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                Text(
                  '${device.durationHours}h • ${device.consumptionKwh.toStringAsFixed(1)} kWh',
                  style: TextStyle(
                    color: device.isEnabled ? null : Colors.grey,
                  ),
                ),
                if (device.getConstraintDescription() != null) ...[
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          device.getConstraintDescription()!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: device.isEnabled,
                  onChanged: (_) => _toggleDevice(device),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editDevice(device);
                    } else if (value == 'delete') {
                      _deleteDevice(device);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Bearbeiten', overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Entfernen', style: TextStyle(color: Colors.red), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dialog to add or edit a planned device
class DeviceEditDialog extends StatefulWidget {
  final PlannedDevice? device; // null = create new device

  const DeviceEditDialog({Key? key, this.device}) : super(key: key);

  @override
  State<DeviceEditDialog> createState() => _DeviceEditDialogState();
}

class _DeviceEditDialogState extends State<DeviceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _durationController;
  late TextEditingController _consumptionController;

  DevicePreset? _selectedPreset;
  IconData _selectedIcon = Icons.power;
  String _selectedCategory = 'other';

  TimeOfDay? _noStartBefore;
  DateTime? _finishBy;

  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.device != null;

    if (_isEditMode) {
      // Edit mode: populate from existing device
      final device = widget.device!;
      _nameController = TextEditingController(text: device.name);
      _durationController = TextEditingController(text: device.durationHours.toString());
      _consumptionController = TextEditingController(text: device.consumptionKwh.toString());
      _selectedIcon = device.icon;
      _selectedCategory = device.category;
      _noStartBefore = device.noStartBefore;
      _finishBy = device.finishBy;
    } else {
      // Create mode: empty fields
      _nameController = TextEditingController();
      _durationController = TextEditingController();
      _consumptionController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _consumptionController.dispose();
    super.dispose();
  }

  void _applyPreset(DevicePreset preset, DeviceProfile profile) {
    setState(() {
      _selectedPreset = preset;
      _nameController.text = '${preset.name} (${profile.name})';
      _durationController.text = profile.durationHours.toString();
      _consumptionController.text = profile.consumptionKwh.toString();
      _selectedIcon = preset.icon;
      _selectedCategory = preset.category;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final device = PlannedDevice(
      id: widget.device?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      category: _selectedCategory,
      presetId: _selectedPreset?.id ?? '',
      icon: _selectedIcon,
      durationHours: double.parse(_durationController.text),
      consumptionKwh: double.parse(_consumptionController.text),
      isEnabled: widget.device?.isEnabled ?? true,
      noStartBefore: _noStartBefore,
      finishBy: _finishBy,
    );

    Navigator.pop(context, device);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            AppBar(
              title: Text(_isEditMode ? 'Gerät bearbeiten' : 'Gerät hinzufügen'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Preset selection (only in create mode)
                      if (!_isEditMode) ...[
                        Text(
                          'Gerät aus Vorlage wählen',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(height: 8),
                        _buildPresetSelection(),
                        SizedBox(height: 24),
                        Divider(),
                        SizedBox(height: 24),
                      ],

                      // Basic info
                      Text(
                        'Gerätedetails',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(_selectedIcon),
                        ),
                        validator: (v) => v?.trim().isEmpty ?? true ? 'Bitte Name eingeben' : null,
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _durationController,
                              decoration: InputDecoration(
                                labelText: 'Dauer (Stunden)',
                                border: OutlineInputBorder(),
                                suffixText: 'h',
                              ),
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                if (v?.trim().isEmpty ?? true) return 'Benötigt';
                                final value = double.tryParse(v!);
                                if (value == null || value <= 0) return 'Ungültig';
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _consumptionController,
                              decoration: InputDecoration(
                                labelText: 'Verbrauch',
                                border: OutlineInputBorder(),
                                suffixText: 'kWh',
                              ),
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                if (v?.trim().isEmpty ?? true) return 'Benötigt';
                                final value = double.tryParse(v!);
                                if (value == null || value <= 0) return 'Ungültig';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 24),
                      Divider(),
                      SizedBox(height: 24),

                      // Time constraints
                      Text(
                        'Zeitliche Einschränkungen (optional)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Definieren Sie, wann das Gerät laufen darf oder fertig sein muss.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                      SizedBox(height: 16),
                      _buildTimeConstraint(
                        label: 'Frühestens starten um',
                        value: _noStartBefore,
                        onChanged: (time) => setState(() => _noStartBefore = time),
                        icon: Icons.access_time,
                      ),
                      SizedBox(height: 12),
                      _buildFinishByConstraint(),

                    ],
                  ),
                ),
              ),
            ),

            // Actions
            Padding(
              padding: EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Abbrechen'),
                  ),
                  ElevatedButton(
                    onPressed: _save,
                    child: Text(_isEditMode ? 'Speichern' : 'Hinzufügen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetSelection() {
    // Scale height based on text scale factor for accessibility
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    final cardHeight = (120 * textScaleFactor.clamp(1.0, 1.5)).toDouble();

    return Container(
      height: cardHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: DevicePresets.all.map((preset) {
          return Container(
            width: 100,
            margin: EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () {
                // Show profile selection dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(preset.name),
                    content: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.6,
                        maxWidth: 400,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: preset.profiles.map((profile) {
                            return ListTile(
                              title: Text(
                                profile.name,
                                overflow: TextOverflow.visible,
                                softWrap: true,
                              ),
                              subtitle: Text('${profile.durationHours}h • ${profile.consumptionKwh} kWh'),
                              onTap: () {
                                Navigator.pop(context);
                                _applyPreset(preset, profile);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: Card(
                color: _selectedPreset?.id == preset.id
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(preset.icon, size: 32),
                      SizedBox(height: 6),
                      Flexible(
                        child: Text(
                          preset.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeConstraint({
    required String label,
    required TimeOfDay? value,
    required Function(TimeOfDay?) onChanged,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: value ?? TimeOfDay.now(),
        );
        if (time != null) {
          onChanged(time);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
          prefixIcon: Icon(icon),
          suffixIcon: value != null
              ? IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () => onChanged(null),
                )
              : null,
        ),
        child: Text(
          value != null
              ? '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} Uhr'
              : 'Keine Einschränkung',
        ),
      ),
    );
  }

  Widget _buildFinishByConstraint() {
    return InkWell(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: _finishBy != null
              ? TimeOfDay.fromDateTime(_finishBy!)
              : TimeOfDay(hour: 22, minute: 0),
        );
        if (time == null) return;

        setState(() {
          // Store as DateTime with today's date (date doesn't matter, only time is checked)
          final now = DateTime.now();
          _finishBy = DateTime(now.year, now.month, now.day, time.hour, time.minute);
        });
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Muss fertig sein bis',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.access_time),
          suffixIcon: _finishBy != null
              ? IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () => setState(() => _finishBy = null),
                )
              : null,
        ),
        child: Text(
          _finishBy != null
              ? '${_finishBy!.hour.toString().padLeft(2, '0')}:${_finishBy!.minute.toString().padLeft(2, '0')} Uhr'
              : 'Keine Einschränkung',
        ),
      ),
    );
  }
}
