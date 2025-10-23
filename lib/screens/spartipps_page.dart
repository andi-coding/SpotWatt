import 'dart:async';
import 'package:flutter/material.dart';
import '../services/savings_tips_service.dart';
import '../services/window_reminder_service.dart';
import '../services/notification_service.dart';

/// Dedicated page for Savings Tips with optimal time windows
class SpartippsPage extends StatefulWidget {
  const SpartippsPage({Key? key}) : super(key: key);

  @override
  State<SpartippsPage> createState() => _SpartippsPageState();
}

class _SpartippsPageState extends State<SpartippsPage> {
  final SavingsTipsService _tipsService = SavingsTipsService();
  final WindowReminderService _reminderService = WindowReminderService();
  List<SavingsTip> _tips = [];
  MonthlySavings? _monthlySavings;
  bool _isLoading = true;
  int _currentPage = 0;
  Map<String, bool> _hasReminder = {}; // Track which windows have reminders
  double _savingsGoal = 500.0; // Default 5€
  Map<String, double> _yearlySavings = {};
  bool _showYearlyOverview = false;
  Timer? _refreshTimer;
  bool _hasDevices = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-refresh every minute to remove expired tips and show new ones
    // This ensures the UI stays current when the app is open
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _loadData(silent: true); // Silent reload without loading spinner
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    // Silent mode: skip loading spinner for automatic background refreshes
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final tips = await _tipsService.calculateSavingsTips();
      final savings = await _tipsService.getMonthlySavings();
      final goal = await _tipsService.getSavingsGoal();
      final yearlySavings = await _tipsService.getYearlySavings();

      // Filter out confirmed tips (hide them from view)
      final unconfirmedTips = tips.where((tip) => !tip.confirmed).toList();

      // Check if user has any devices configured (confirmed or not)
      final hasDevices = tips.isNotEmpty;

      // Load reminder status for each tip
      final reminderStatus = <String, bool>{};
      for (final tip in unconfirmedTips) {
        final key = '${tip.deviceWindow.device.id}_${tip.deviceWindow.window.startTime.toIso8601String()}';
        reminderStatus[key] = await _reminderService.hasReminder(
          tip.deviceWindow.device.id,
          tip.deviceWindow.window.startTime,
        );
      }

      if (mounted) {
        setState(() {
          _tips = unconfirmedTips;
          _monthlySavings = savings;
          _hasDevices = hasDevices;
          _hasReminder = reminderStatus;
          _savingsGoal = goal;
          _yearlySavings = yearlySavings;
          _isLoading = false;

          // Reset page to 0 if current page is out of bounds
          if (_currentPage >= unconfirmedTips.length && unconfirmedTips.isNotEmpty) {
            _currentPage = 0;
          }
        });
      }
    } catch (e) {
      debugPrint('[SpartippsPage] Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmTip(SavingsTip tip) async {
    await _tipsService.confirmTip(tip);

    // Show undo toast
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Gespeichert (${tip.savingsFormatted})'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Rückgängig',
            onPressed: () async {
              await _tipsService.undoConfirmTip(tip);
              await _loadData();
            },
          ),
        ),
      );
    }

    await _loadData(); // Reload to update UI
  }

  Future<void> _dismissTip(SavingsTip tip) async {
    await _tipsService.dismissTip(tip);

    // Show undo toast
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Tipp ausgeblendet'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Rückgängig',
            onPressed: () async {
              await _tipsService.undoDismissTip(tip);
              await _loadData();
            },
          ),
        ),
      );
    }

    await _loadData(); // Reload to update UI
  }

  Future<void> _toggleReminder(SavingsTip tip) async {
    final key = '${tip.deviceWindow.device.id}_${tip.deviceWindow.window.startTime.toIso8601String()}';
    final hasReminder = _hasReminder[key] ?? false;

    if (hasReminder) {
      // Cancel the notification FIRST (needs reminder data from storage)
      await NotificationService().cancelWindowReminder(key);

      // THEN remove reminder from storage
      await _reminderService.removeReminder(key);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erinnerung entfernt'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Update reminder state
      setState(() {
        _hasReminder[key] = false;
      });
    } else {
      // Check if reminder can still be set
      final now = DateTime.now();
      final windowStart = tip.deviceWindow.window.startTime;
      final windowEnd = tip.deviceWindow.window.endTime;

      // Check 1: Is window already over?
      if (windowEnd.isBefore(now)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏰ Zeitfenster ist bereits vorbei!'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Check 2: Is window currently running?
      if (windowStart.isBefore(now) && windowEnd.isAfter(now)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Zeitfenster läuft bereits! Gerät jetzt einschalten!'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
        return;
      }

      // Check 3: Is notification time already passed? (< 5 min until start)
      final minutesBefore = _reminderService.reminderMinutesBefore;
      final notificationTime = windowStart.subtract(Duration(minutes: minutesBefore));

      if (notificationTime.isBefore(now)) {
        final minutesUntilStart = windowStart.difference(now).inMinutes;

        if (minutesUntilStart > 0) {
          // Window starts soon (< 5 min), but hasn't started yet
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚡ Zeitfenster startet in $minutesUntilStart Min! Gerät jetzt bereit machen!'),
                duration: const Duration(seconds: 4),
                backgroundColor: Colors.orange.shade700,
              ),
            );
          }
        }
        return;
      }

      // All checks passed - add reminder
      final reminder = WindowReminder(
        deviceId: tip.deviceWindow.device.id,
        deviceName: tip.deviceWindow.device.name,
        startTime: tip.deviceWindow.window.startTime,
        endTime: tip.deviceWindow.window.endTime,
        savingsCents: tip.deviceWindow.savings,
      );

      await _reminderService.addReminder(reminder);

      // Schedule notification immediately
      await NotificationService().scheduleWindowReminder(reminder);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erinnerung $minutesBefore Min. vorher aktiviert'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Update reminder state
      setState(() {
        _hasReminder[key] = true;
      });
    }
  }

  void _showGoalSettingsSheet(ThemeData theme) {
    double tempGoal = _savingsGoal;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.flag,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Monatliches Sparziel',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Setze dein persönliches Sparziel für jeden Monat',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Current goal display
              Center(
                child: Column(
                  children: [
                    Text(
                      'Dein Ziel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(tempGoal / 100).toStringAsFixed(2)}€',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0€',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '20€',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: tempGoal,
                    min: 0,
                    max: 2000, // 20€ in cents
                    divisions: 40, // 0.50€ increments
                    onChanged: (value) {
                      setModalState(() {
                        tempGoal = value;
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await _tipsService.setSavingsGoal(tempGoal);
                    setState(() {
                      _savingsGoal = tempGoal;
                    });
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Sparziel gespeichert: ${(tempGoal / 100).toStringAsFixed(2)}€',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Sparziel speichern'),
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfoDialog(ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wie funktionieren Spartipps?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SpotWatt berechnet für jedes Gerät das günstigste Zeitfenster.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Die Ersparnis zeigt den Unterschied zum teuersten möglichen Zeitfenster.',
              ),
              const SizedBox(height: 16),
              Text(
                'Beispiel:',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '• Optimal: 0.70€ (15:00-17:00)',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '• Teuerste Zeit: 1.50€ (18:00-20:00)',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '• Ersparnis: 0.80€',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spartipps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _buildContent(theme),
            ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with info
          _buildHeader(theme),
          const SizedBox(height: 24),

          // Tips content
          if (_tips.isEmpty && !_hasDevices)
            _buildEmpty()
          else if (_tips.isEmpty && _hasDevices)
            _buildAllConfirmed()
          else
            _buildTipsList(theme),

          // Monthly savings summary
          if (_monthlySavings != null && _monthlySavings!.totalSavings > 0) ...[
            const SizedBox(height: 24),
            _buildMonthlySummary(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(
          Icons.lightbulb_outline,
          color: Colors.green.shade700,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Optimale Zeitfenster',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Spare durch optimale Nutzung deiner Geräte',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_tips.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${_tips.length}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            Icons.info_outline,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          onPressed: () => _showInfoDialog(theme),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(
              Icons.energy_savings_leaf_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              'Keine Spartipps verfügbar',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Füge Geräte hinzu, um optimale Zeiten zu sehen',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/device-management');
              },
              icon: const Icon(Icons.add),
              label: const Text('Geräte hinzufügen'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllConfirmed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.green.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              'Alle Geräte optimal genutzt!',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Neue Spartipps verfügbar sobald die Preise für morgen da sind.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsList(ThemeData theme) {
    // Scale height dynamically based on text scale factor AND display size
    final mediaQuery = MediaQuery.of(context);
    final textScaleFactor = mediaQuery.textScaleFactor;
    final screenHeight = mediaQuery.size.height;

    // Debug: Print to understand display size scaling
    print('[Spartipps] textScale: $textScaleFactor, screenHeight: $screenHeight');

    // Base formula + screen height compensation for display size changes
    // Smaller screens (large display size setting) need proportionally more height
    // Added +20 for X-button height increase
    final displaySizeCompensation = (900 - screenHeight).clamp(0, 200) / 5;
    final cardHeight = (310 + (textScaleFactor - 1.0) * 220 + displaySizeCompensation).toDouble();

    print('[Spartipps] compensation: $displaySizeCompensation, cardHeight: $cardHeight');

    return Column(
      children: [
        // Swipeable PageView
        SizedBox(
          height: cardHeight,
          child: PageView.builder(
            itemCount: _tips.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              return _buildTipItem(_tips[index], theme);
            },
          ),
        ),

        // Page indicators
        if (_tips.length > 1) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_tips.length, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == index ? 32 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? theme.colorScheme.primary
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildTipItem(SavingsTip tip, ThemeData theme) {
    final device = tip.deviceWindow.device;
    final isRunning = tip.deviceWindow.isRunning;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRunning
            ? (theme.brightness == Brightness.dark
                ? Colors.green.withOpacity(0.15)
                : Colors.green.shade50)
            : theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning
              ? (theme.brightness == Brightness.dark
                  ? Colors.green.shade700
                  : Colors.green.shade200)
              : theme.colorScheme.outline.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Device icon + name with dismiss button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  device.icon,
                  size: 32,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Device name
                    Text(
                      device.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                    const SizedBox(height: 4),
                    // Duration and kWh consumption
                    Text(
                      '${device.durationHours}h, ${device.consumptionKwh.toStringAsFixed(1)} kWh',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Time window - prominent
                    Text(
                      tip.subtitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isRunning
                            ? Colors.green.shade700
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Dismiss button (X)
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
                onPressed: () => _dismissTip(tip),
                tooltip: 'Tipp ausblenden',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Savings amount - Compact card design
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.green.withOpacity(0.15)
                  : Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.brightness == Brightness.dark
                    ? Colors.green.shade700
                    : Colors.green.shade200,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.savings,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Spare: ${tip.savingsFormatted}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Kosten: ${tip.optimalCostFormatted} statt ${tip.worstCostFormatted}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action buttons row
          Row(
            children: [
              // Confirm button
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: () => _confirmTip(tip),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  ),
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text(
                    'Gerät eingeschaltet',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Reminder button
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () => _toggleReminder(tip),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  ),
                  child: Icon(
                    _hasReminder['${tip.deviceWindow.device.id}_${tip.deviceWindow.window.startTime.toIso8601String()}'] ?? false
                        ? Icons.notifications_active
                        : Icons.notifications_outlined,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySummary(ThemeData theme) {
    final currentSavings = _monthlySavings!.totalSavings;
    final progress = (currentSavings / _savingsGoal).clamp(0.0, 1.0);
    final goalReached = currentSavings >= _savingsGoal;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with goal and settings
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Diesen Monat gespart',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_monthlySavings!.confirmedCount} Geräte optimal genutzt',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _monthlySavings!.formattedTotal,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: goalReached ? Colors.green.shade700 : Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Progress bar with goal reached badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Monatsziel',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              '${(currentSavings / 100).toStringAsFixed(2)}€ / ${(_savingsGoal / 100).toStringAsFixed(2)}€',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _showGoalSettingsSheet(theme),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.settings,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          goalReached ? Colors.green.shade700 : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    // Goal reached badge overlay
                    if (goalReached)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.celebration,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ziel erreicht!',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Yearly overview toggle
            if (_yearlySavings.isNotEmpty) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: () {
                  setState(() {
                    _showYearlyOverview = !_showYearlyOverview;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Jahresübersicht',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _showYearlyOverview ? Icons.expand_less : Icons.expand_more,
                        size: 24,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),

              // Yearly overview expanded
              if (_showYearlyOverview) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._yearlySavings.entries.map((entry) {
                        final monthYear = entry.key;
                        final savings = entry.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                monthYear,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                '${(savings / 100).toStringAsFixed(2)}€',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Gesamt',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${(_yearlySavings.values.fold(0.0, (sum, val) => sum + val) / 100).toStringAsFixed(2)}€',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed('/device-management');
                },
                icon: const Icon(Icons.power, size: 20),
                label: const Text('Geräte verwalten'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
