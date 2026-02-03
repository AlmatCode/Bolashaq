// lib/screens/tickets_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:clipboard/clipboard.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  // Состояние
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // Данные
  Map<String, dynamic>? _activeTicket;
  List<Map<String, dynamic>> _usageHistory = [];
  String? _dailyQrToken;
  DateTime? _qrGeneratedAt;
  bool _isTodayUsed = false;

  // Анимации
  late AnimationController _qrAnimationController;
  late Animation<double> _qrScaleAnimation;
  late Animation<Color?> _qrColorAnimation;

  // Таймер для обновления QR-кода
  Timer? _qrRefreshTimer;
  Timer? _usageCheckTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Инициализация анимаций
    _qrAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _qrScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.98, end: 1.02), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.02, end: 0.98), weight: 50),
    ]).animate(
      CurvedAnimation(
        parent: _qrAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _qrColorAnimation = ColorTween(
      begin: AppColors.primary.withOpacity(0.7),
      end: AppColors.primary.withOpacity(0.9),
    ).animate(
      CurvedAnimation(
        parent: _qrAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Загрузка данных
    _loadData();

    // Запускаем таймер для обновления QR каждые 24 часа
    _startTimers();

    // Защита от скриншотов
    _enableScreenshotProtection();
  }

  @override
  void dispose() {
    _qrAnimationController.dispose();
    _qrRefreshTimer?.cancel();
    _usageCheckTimer?.cancel();
    _disableScreenshotProtection();
    super.dispose();
  }

  void _enableScreenshotProtection() {
    if (Platform.isAndroid) {
      // Для Android используем FLAG_SECURE
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // В реальном приложении используйте flutter_windowmanager или аналогичный пакет
    }
  }

  void _disableScreenshotProtection() {
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    }
  }

  void _startTimers() {
    // Таймер для ежедневного обновления QR
    _qrRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _checkAndUpdateQR();
    });

    // Таймер для проверки использования
    _usageCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkTodayUsage();
    });
  }

  Future<void> _checkAndUpdateQR() async {
    final now = DateTime.now();
    if (_qrGeneratedAt == null ||
        now.difference(_qrGeneratedAt!).inHours >= 24) {
      await _generateDailyQrToken();
    }
  }

  Future<void> _checkTodayUsage() async {
    if (_activeTicket == null) return;

    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final usage = await _supabase
          .from('ticket_usage')
          .select('*')
          .eq('ticket_id', _activeTicket!['id'])
          .eq('used_date', today)
          .not('used_time', 'is', null) // Используем used_time вместо used
          .maybeSingle();

      setState(() {
        _isTodayUsed = usage != null;
      });
    } catch (e) {
      debugPrint('Error checking usage: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final user = _supabase.auth.currentUser;
      if (user == null) {
        _redirectToLogin();
        return;
      }

      // Загружаем активный талон
      final today = DateTime.now().toIso8601String().split('T')[0];
      final ticketResponse = await _supabase
          .from('tickets')
          .select('*')
          .eq('student_id', user.id)
          .eq('is_active', true)
          .lte('start_date', today)  // ✅ start_date <= today
          .gte('end_date', today)    // ✅ end_date >= today
          .maybeSingle();

      if (ticketResponse != null) {
        final ticket = Map<String, dynamic>.from(ticketResponse);

        // Получаем информацию о студенте из profiles
        final profileResponse = await _supabase
            .from('profiles')
            .select('full_name, student_group')
            .eq('id', user.id)
            .single();

        // Объединяем данные
        ticket['student_info'] = {
          'full_name': profileResponse['full_name'],
          'student_group': profileResponse['student_group']
        };

        setState(() => _activeTicket = ticket);

        // Загружаем историю использования
        await _loadUsageHistory(ticket['id']);

        // Генерируем/получаем ежедневный QR
        await _generateDailyQrToken();

        // Проверяем использование сегодня
        await _checkTodayUsage();
      } else {
        setState(() {
          _activeTicket = null;
          _dailyQrToken = null;
          _usageHistory = [];
        });
      }

    } catch (error) {
      debugPrint('Error loading tickets: $error');
      setState(() {
        _errorMessage = 'Не удалось загрузить данные. Проверьте подключение.';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _loadUsageHistory(String ticketId) async {
    try {
      final historyResponse = await _supabase
          .from('ticket_usage')
          .select('''
          *,
          profiles!inner(full_name)
        ''')
          .eq('ticket_id', ticketId)
          .order('used_date', ascending: false)
          .limit(30);

      final List<Map<String, dynamic>> enrichedHistory = [];

      for (var usage in historyResponse) {
        final Map<String, dynamic> usageData = Map<String, dynamic>.from(usage);

        // Получаем имя кассира
        if (usage['profiles'] != null) {
          usageData['cashier_name'] = usage['profiles']['full_name'];
        }

        // Добавляем флаг использованности
        usageData['is_used'] = usage['used_time'] != null;

        enrichedHistory.add(usageData);
      }

      setState(() {
        _usageHistory = enrichedHistory;
      });

    } catch (e) {
      debugPrint('Error loading usage history: $e');

      // Fallback: загружаем без вложенного запроса
      try {
        final historyResponse = await _supabase
            .from('ticket_usage')
            .select('*')
            .eq('ticket_id', ticketId)
            .order('used_date', ascending: false)
            .limit(30);

        // Получаем имена кассиров отдельно
        final List<Map<String, dynamic>> enrichedHistory = [];

        for (var usage in historyResponse) {
          final Map<String, dynamic> usageData = Map<String, dynamic>.from(usage);

          if (usage['scanned_by'] != null) {
            try {
              final cashierProfile = await _supabase
                  .from('profiles')
                  .select('full_name')
                  .eq('id', usage['scanned_by'])
                  .maybeSingle();

              if (cashierProfile != null) {
                usageData['cashier_name'] = cashierProfile['full_name'];
              }
            } catch (e) {
              debugPrint('Error loading cashier profile: $e');
            }
          }

          usageData['is_used'] = usage['used_time'] != null;
          enrichedHistory.add(usageData);
        }

        setState(() {
          _usageHistory = enrichedHistory;
        });
      } catch (fallbackError) {
        debugPrint('Fallback error: $fallbackError');
      }
    }
  }

  Future<void> _generateDailyQrToken() async {
    if (_activeTicket == null) return;

    try {
      // Используем локальное время для Алматы
      final now = DateTime.now().toLocal();
      final today = DateFormat('yyyy-MM-dd').format(now);

      // expires_at в Алматы (23:59:59)
      final expiresAt = DateTime(
        now.year,
        now.month,
        now.day,
        23, // 23:59:59 Алматы
        59,
        59,
      );

      // Проверяем существующий токен для сегодняшней даты
      final existingToken = await _supabase
          .from('daily_qr_codes')
          .select('token')
          .eq('ticket_id', _activeTicket!['id'])
          .eq('date', today)
          .eq('used', false)
          .maybeSingle();

      String qrToken;

      if (existingToken != null) {
        qrToken = existingToken['token'];
      } else {
        qrToken = _generateSecureToken(16);

        await _supabase.from('daily_qr_codes').insert({
          'ticket_id': _activeTicket!['id'],
          'date': today,
          'token': qrToken,
          'generated_at': now.toIso8601String(),
          'expires_at': expiresAt.toIso8601String(),
          'used': false,
        });
      }

      setState(() {
        _dailyQrToken = qrToken;
        _qrGeneratedAt = now;
      });

    } catch (error) {
      debugPrint('Error generating QR token: $error');
      // Fallback - генерируем случайный токен
      setState(() {
        _dailyQrToken = _generateSecureToken(16);
        _qrGeneratedAt = DateTime.now();
      });
    }
  }

  String _generateSecureToken(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/login');
    });
  }

  Future<void> _copyTokenToClipboard() async {
    if (_dailyQrToken == null) return;

    await FlutterClipboard.copy(_dailyQrToken!);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Токен скопирован в буфер обмена'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showTicketDetails() async {
    if (_activeTicket == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TicketDetailsSheet(
        ticket: _activeTicket!,
        usageHistory: _usageHistory,
        isTodayUsed: _isTodayUsed,
      ),
    );
  }

  Future<void> _refreshData() async {
    _refreshKey.currentState?.show();
    await _loadData();
  }

  Widget _buildNoTicketView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.confirmation_number_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'У вас нет активных талонов',
              style: AppTypography.headlineSmall.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Обратитесь к администратору колледжа\nдля получения талона',
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTicketView() {
    final startDate = DateTime.parse(_activeTicket!['start_date']);
    final endDate = DateTime.parse(_activeTicket!['end_date']);
    final now = DateTime.now();
    final daysTotal = endDate.difference(startDate).inDays + 1;
    final daysPassed = now.difference(startDate).inDays + 1;
    final daysLeft = endDate.difference(now).inDays;
    final usedCount = _usageHistory.where((u) => u['is_used'] == true).length;

    return Column(
      children: [
        // Карточка талона
        ModernCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок и статус
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Талоны на питание',
                    style: AppTypography.headlineSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Text(
                      'Активен',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Информация о периоде
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${DateFormat('dd.MM.yyyy').format(startDate)} - ${DateFormat('dd.MM.yyyy').format(endDate)}',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Прогресс и статистика
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // Прогресс бар
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: daysPassed / daysTotal,
                            backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            color: AppColors.primary,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$daysPassed/$daysTotal дней',
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Статистика в ряд
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          'Использовано',
                          '$usedCount раз',
                          Icons.check_circle,
                          AppColors.success,
                        ),
                        _buildStatItem(
                          'Осталось дней',
                          '$daysLeft',
                          Icons.timer,
                          AppColors.warning,
                        ),
                        _buildStatItem(
                          'Сегодня',
                          _isTodayUsed ? 'Использован' : 'Доступен',
                          _isTodayUsed ? Icons.done_all : Icons.event_available,
                          _isTodayUsed ? AppColors.success : AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Кнопка деталей
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showTicketDetails,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Подробная информация'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // QR-код
        ModernCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'QR-код на сегодня',
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Действителен до ${_qrGeneratedAt?.add(const Duration(hours: 24)).toIso8601String().split('T')[1].substring(0, 5) ?? '--:--'}',
                style: AppTypography.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),

              const SizedBox(height: 24),

              // Контейнер с QR-кодом
              AnimatedBuilder(
                animation: _qrScaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _qrScaleAnimation.value,
                    child: Container(
                      width: 220,
                      height: 220,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _qrColorAnimation.value!,
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: _dailyQrToken != null
                          ? QrImageView(
                        data: 'TICKET:${_activeTicket!['id'].toString()}:$_dailyQrToken',
                        version: QrVersions.auto,
                        size: 180,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      )
                          : const CircularProgressIndicator(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Информация под QR
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isTodayUsed
                            ? 'Вы уже использовали талон сегодня'
                            : 'Покажите QR-код кассиру для получения питания',
                        style: AppTypography.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Кнопки действий
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _dailyQrToken != null ? _copyTokenToClipboard : null,
                      icon: const Icon(Icons.copy),
                      label: const Text('Копировать токен'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _refreshData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // История использования
        if (_usageHistory.isNotEmpty) ...[
          ModernCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'История использования',
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ..._usageHistory.take(5).map((usage) {
                  final date = DateTime.parse(usage['used_date']); // вместо usage['date']
                  final cashierName = usage['cashier_name'] ?? 'Кассир';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: usage['is_used'] == true
                          ? AppColors.success.withOpacity(0.05)
                          : AppColors.warning.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: usage['is_used'] == true
                            ? AppColors.success.withOpacity(0.2)
                            : AppColors.warning.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          usage['is_used'] == true ? Icons.check_circle : Icons.pending,
                          color: usage['is_used'] == true ? AppColors.success : AppColors.warning,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('dd MMMM yyyy', 'ru_RU').format(date),
                                style: AppTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                usage['is_used'] == true
                                    ? 'Использован у $cashierName'
                                    : 'Не использован',
                                style: AppTypography.bodySmall.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),

                if (_usageHistory.length > 5)
                  TextButton(
                    onPressed: () => _showFullHistory(),
                    child: const Text('Показать всю историю'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Future<void> _showFullHistory() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FullHistorySheet(history: _usageHistory),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Талоны'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(),
            tooltip: 'Помощь',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        key: _refreshKey,
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: _activeTicket == null
              ? _buildNoTicketView()
              : _buildActiveTicketView(),
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Как пользоваться талонами?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpItem(
                'QR-код обновляется каждый день',
                'Новый QR-код генерируется автоматически каждые 24 часа',
              ),
              const SizedBox(height: 12),
              _buildHelpItem(
                'Один QR-код в день',
                'Каждый QR-код можно использовать только один раз в день',
              ),
              const SizedBox(height: 12),
              _buildHelpItem(
                'Срок действия талона',
                'Талон активен в течение установленного администратором периода',
              ),
              const SizedBox(height: 12),
              _buildHelpItem(
                'Если QR-код не работает',
                'Нажмите "Обновить" или обратитесь к администратору',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: AppTypography.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}

// Модальное окно с деталями талона
class _TicketDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final List<Map<String, dynamic>> usageHistory;
  final bool isTodayUsed;

  const _TicketDetailsSheet({
    required this.ticket,
    required this.usageHistory,
    required this.isTodayUsed,
  });

  @override
  Widget build(BuildContext context) {
    final startDate = DateTime.parse(ticket['start_date']);
    final endDate = DateTime.parse(ticket['end_date']);
    final periodType = ticket['period_type'];
    final studentName = ticket['student_info']?['full_name'] ?? 'Студент';
    final group = ticket['student_info']?['student_group'] ?? 'Группа не указана';
    final usedCount = usageHistory.where((u) => u['is_used'] == true).length;
    final missedCount = usageHistory.where((u) => u['is_used'] == false).length;
    final totalDays = endDate.difference(startDate).inDays + 1;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.confirmation_number,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Детали талона',
                              style: AppTypography.headlineSmall.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$studentName • $group',
                              style: AppTypography.bodyMedium.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Основная информация
                  ModernCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          context,
                          'Период действия:',
                          '${DateFormat('dd.MM.yyyy').format(startDate)} - ${DateFormat('dd.MM.yyyy').format(endDate)}',
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          context,
                          'Тип периода:',
                          _getPeriodTypeName(periodType),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          context,
                          'Всего дней:',
                          '$totalDays',
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          context,
                          'Использовано дней:',
                          '$usedCount',
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          context,
                          'Пропущено дней:',
                          '$missedCount',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Статистика использования
                  Text(
                    'Статистика использования',
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Прогресс использования
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Процент использования',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: totalDays > 0 ? usedCount / totalDays : 0,
                                    backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                    color: usedCount / totalDays > 0.7 ? AppColors.success : AppColors.warning,
                                    minHeight: 10,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              totalDays > 0 ? '${((usedCount / totalDays) * 100).round()}%' : '0%',
                              style: AppTypography.headlineSmall.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Диаграмма использования по дням
                        if (usageHistory.isNotEmpty) ...[
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 7,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            children: usageHistory.take(14).map((usage) {
                              final isUsed = usage['is_used'] == true;
                              return Container(
                                decoration: BoxDecoration(
                                  color: isUsed ? AppColors.success : AppColors.warning,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Center(
                                  child: Icon(
                                    isUsed ? Icons.check : Icons.close,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Последние 14 дней',
                            style: AppTypography.bodySmall.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Статус на сегодня
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isTodayUsed
                          ? AppColors.success.withOpacity(0.1)
                          : AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isTodayUsed ? AppColors.success : AppColors.primary,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isTodayUsed ? Icons.check_circle : Icons.event_available,
                          color: isTodayUsed ? AppColors.success : AppColors.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isTodayUsed ? 'Сегодня уже поели' : 'Сегодня можно поесть',
                                style: AppTypography.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isTodayUsed
                                    ? 'Вы использовали талон сегодня'
                                    : 'QR-код действителен до конца дня',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Кнопка закрытия
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Закрыть'),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right, // ✅ ВОТ СЮДА
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _getPeriodTypeName(String periodType) {
    switch (periodType) {
      case 'month':
        return 'Месяц';
      case 'week':
        return 'Неделя';
      case 'day':
        return 'День';
      default:
        return periodType;
    }
  }
}

// Модальное окно полной истории
class _FullHistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> history;

  const _FullHistorySheet({required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Вся история использования',
                    style: AppTypography.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final usage = history[index];
                  final date = DateTime.parse(usage['used_date']); // вместо usage['date']
                  final isUsed = usage['is_used'] == true;
                  final cashierName = usage['cashier_name'];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isUsed ? AppColors.success : AppColors.warning,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            isUsed ? Icons.check : Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('EEEE, d MMMM yyyy', 'ru_RU').format(date),
                                style: AppTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (cashierName != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Кассир: $cashierName',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ModernCard виджет
class ModernCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const ModernCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}