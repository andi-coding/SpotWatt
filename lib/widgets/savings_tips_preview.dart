import 'dart:async';
import 'package:flutter/material.dart';
import '../services/savings_tips_service.dart';

/// Notification to navigate to Spartipps tab
class SpartippsNavigationNotification extends Notification {}

/// Minimal preview of best savings tip - links to full Spartipps page
class SavingsTipsPreview extends StatefulWidget {
  const SavingsTipsPreview({Key? key}) : super(key: key);

  @override
  State<SavingsTipsPreview> createState() => _SavingsTipsPreviewState();
}

class _SavingsTipsPreviewState extends State<SavingsTipsPreview> {
  final SavingsTipsService _tipsService = SavingsTipsService();
  SavingsTip? _bestTip;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadBestTip();
    // Auto-refresh every minute to update best tip and remove expired ones
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _loadBestTip();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBestTip() async {
    try {
      final tips = await _tipsService.calculateSavingsTips();

      // Filter out confirmed tips
      final unconfirmedTips = tips.where((tip) => !tip.confirmed).toList();

      // Get the next best tip (chronologically next, with highest savings if same time)
      // This ensures consistency with Spartipps page which shows tips chronologically
      if (unconfirmedTips.isNotEmpty) {
        unconfirmedTips.sort((a, b) {
          // Sort by start time first (earlier = better)
          final timeCompare = a.deviceWindow.window.startTime.compareTo(b.deviceWindow.window.startTime);
          if (timeCompare != 0) return timeCompare;
          // If same time, prefer higher savings
          return b.deviceWindow.savings.compareTo(a.deviceWindow.savings);
        });
        if (mounted) {
          setState(() {
            _bestTip = unconfirmedTips.first;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _bestTip = null;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[SavingsTipsPreview] Error loading best tip: $e');
      if (mounted) {
        setState(() {
          _bestTip = null;
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToSpartipps() {
    // Find the HomeScreen context and trigger tab change
    // We use a custom notification to bubble up the event
    SpartippsNavigationNotification().dispatch(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink(); // Don't show anything while loading
    }

    if (_bestTip == null) {
      return const SizedBox.shrink(); // No tips available
    }

    final theme = Theme.of(context);
    final device = _bestTip!.deviceWindow.device;
    final isRunning = _bestTip!.deviceWindow.isRunning;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: _navigateToSpartipps,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isRunning
                      ? Colors.green.shade100
                      : theme.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  device.icon,
                  size: 20,
                  color: isRunning
                      ? Colors.green.shade700
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 14,
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Spartipp:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.name} • ${_bestTip!.subtitle.split('\n').first}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isRunning ? Colors.green.shade700 : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Spare ${_bestTip!.savingsFormatted}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
