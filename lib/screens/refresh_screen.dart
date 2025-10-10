import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/widget_service.dart';
import '../services/background_task_service.dart';
import '../services/price_cache_service.dart';

/// Transparent screen that refreshes widget and closes automatically
/// Triggered by tapping refresh button on home widget
class RefreshScreen extends StatefulWidget {
  const RefreshScreen({Key? key}) : super(key: key);

  @override
  State<RefreshScreen> createState() => _RefreshScreenState();
}

class _RefreshScreenState extends State<RefreshScreen> {
  @override
  void initState() {
    super.initState();
    _performRefresh();
  }

  Future<void> _performRefresh() async {
    try {
      debugPrint('[RefreshScreen] Starting widget refresh...');

      // 1. Force reload prices from API
      final priceCacheService = PriceCacheService();
      await priceCacheService.getPrices();
      debugPrint('[RefreshScreen] Prices refreshed');

      // 2. Update widget with new data
      await WidgetService.updateWidget();
      debugPrint('[RefreshScreen] Widget updated');

      // 3. Reschedule WorkManager (in case OEM killed it)
      await BackgroundTaskService.reschedule();
      debugPrint('[RefreshScreen] Background tasks rescheduled');

      // Close the activity immediately after all operations complete
      if (mounted) {
        SystemNavigator.pop();
      }
    } catch (e) {
      debugPrint('[RefreshScreen] Refresh failed: $e');
      // Close even on error
      if (mounted) {
        SystemNavigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 140,
            maxHeight: 140,
          ),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // SpotWatt Logo
              Image.asset(
                'assets/icons/spotwatt_logo_final.png',
                width: 48,
                height: 48,
              ),
              const SizedBox(height: 16),
              // Spinner
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1e3a5f)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
