import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../core/theme.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';

class ScheduleScreen extends StatefulWidget {
  final String? initialDateIso;
  final bool forceRefresh;

  const ScheduleScreen({
    super.key,
    this.initialDateIso,
    this.forceRefresh = false,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Состояние
  bool _isLoading = true;
  bool _refreshing = false;
  String? _error;
  Map<String, dynamic>? _profile;

  // Данные
  List<Map<String, dynamic>> _scheduleItems = [];
  List<Map<String, dynamic>> _detailedScheduleItems = [];
  Map<DateTime, List<Map<String, dynamic>>> _groupedByDay = {};
  Map<String, List<Map<String, dynamic>>> _groupedByCourse = {};

  // Фильтры и настройки
  String _viewMode = 'calendar'; // calendar | list | week
  String _selectedCourse = 'all';
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  DateTime _firstDay = DateTime.now().subtract(const Duration(days: 365));
  DateTime _lastDay = DateTime.now().add(const Duration(days: 365));

  // Поиск
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Анимации
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Инициализация дат
    if (widget.initialDateIso != null) {
      try {
        _selectedDay = DateTime.parse(widget.initialDateIso!);
        _focusedDay = _selectedDay;
      } catch (_) {}
    }

    // Настройка анимаций
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    // Загрузка данных
    _loadData();

    // Подписка на realtime изменения
    _setupRealtimeSubscription();
  }

  @override
  void didUpdateWidget(covariant ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceRefresh) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      // Загружаем профиль пользователя для получения его группы
      final profileResp = await _supabase
          .from('profiles')
          .select('student_group, role')
          .eq('id', user.id)
          .single();

      _profile = Map<String, dynamic>.from(profileResp);
      final studentGroup = _profile?['student_group'] as String?;
      final userRole = _profile?['role'] as String? ?? 'student';

      // Загружаем расписание
      // ВАЖНО: У нас есть две таблицы с расписанием:
      // 1. schedule (простое расписание)
      // 2. detailed_schedules (детальное расписание)

      List<Map<String, dynamic>> allScheduleItems = [];

      // Загружаем из detailed_schedules
      try {

  } catch (e) {
    print('Ошибка загрузки detailed_schedules: $e');
    }

    // Загружаем из schedule (основное расписание)
    try {
    final scheduleQuery = _supabase
        .from('schedule')
        .select('''
              id, subject, teacher, room, 
              day_of_week, start_time, end_time,
              lesson_type, group_name, semester, academic_year
            ''');

    // Фильтруем по группе если пользователь студент
    if (studentGroup != null && studentGroup.isNotEmpty) {
    scheduleQuery.eq('group_name', studentGroup);
    }

    final scheduleResp = await scheduleQuery
        .order('day_of_week')
        .order('start_time')
        .timeout(const Duration(seconds: 10));

    final scheduleItems = (scheduleResp is List)
    ? List<Map<String, dynamic>>.from(scheduleResp)
        : <Map<String, dynamic>>[];

    // Преобразуем расписание из schedule в формат для отображения
    for (final item in scheduleItems) {
    // Создаем дату на основе дня недели
    final dayOfWeek = item['day_of_week'] as String;
    final startTimeStr = item['start_time'] as String;
    final endTimeStr = item['end_time'] as String;

    // Получаем дату для выбранного дня недели
    final scheduleDate = _getDateForDayOfWeek(dayOfWeek, _selectedDay);

    if (scheduleDate != null) {
    // Создаем полные даты
    final startDateTime = DateTime(
    scheduleDate.year,
    scheduleDate.month,
    scheduleDate.day,
    _parseTime(startTimeStr).hour,
    _parseTime(startTimeStr).minute,
    );

    final endDateTime = DateTime(
    scheduleDate.year,
    scheduleDate.month,
    scheduleDate.day,
    _parseTime(endTimeStr).hour,
    _parseTime(endTimeStr).minute,
    );

    allScheduleItems.add({
    'id': item['id'],
    'title': item['subject'],
    'subject': item['subject'],
    'start_time': startDateTime.toIso8601String(),
    'end_time': endDateTime.toIso8601String(),
    'teacher_name': item['teacher'],
    'room': item['room'],
    'type': item['lesson_type'] ?? 'lecture',
    'group_name': item['group_name'],
    'day_of_week': dayOfWeek,
    'semester': item['semester'],
    'academic_year': item['academic_year'],
    'source': 'schedule', // Для идентификации источника
    });
    }
    }
    } catch (e) {
    print('Ошибка загрузки schedule: $e');
    }

    // Группируем данные
    _groupScheduleData(allScheduleItems);

    if (!mounted) return;
    setState(() {
    _scheduleItems = allScheduleItems;
    });

    // Запускаем анимацию
    _animationController.forward(from: 0);
    } on TimeoutException catch (e) {
    if (!mounted) return;
    setState(() {
    _error = 'Таймаут загрузки. Проверьте подключение к интернету';
    });
    } on PostgrestException catch (e) {
    if (!mounted) return;
    setState(() {
    _error = 'Ошибка базы данных: ${e.message}';
    });
    } catch (e) {
    if (!mounted) return;
    setState(() {
    _error = 'Ошибка загрузки расписания: $e';
    });
    } finally {
    if (mounted) {
    setState(() => _isLoading = false);
    }
    }
  }

  DateTime? _getDateForDayOfWeek(String dayOfWeek, DateTime referenceDate) {
    final dayMap = {
      'Понедельник': 1,
      'Вторник': 2,
      'Среда': 3,
      'Четверг': 4,
      'Пятница': 5,
      'Суббота': 6,
      'Воскресенье': 7,
    };

    final targetDay = dayMap[dayOfWeek];
    if (targetDay == null) return null;

    final currentDay = referenceDate.weekday;
    final difference = targetDay - currentDay;

    return referenceDate.add(Duration(days: difference));
  }

  DateTime _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  void _groupScheduleData(List<Map<String, dynamic>> items) {
    _groupedByDay.clear();
    _groupedByCourse.clear();

    for (final item in items) {
      final startTime = DateTime.tryParse(item['start_time'] as String? ?? '');
      if (startTime == null) continue;

      // Группировка по дням
      final day = DateTime(startTime.year, startTime.month, startTime.day);
      _groupedByDay.putIfAbsent(day, () => []).add(item);

      // Группировка по предметам (курсам)
      final course = item['subject'] as String? ?? item['title'] as String? ?? 'other';
      _groupedByCourse.putIfAbsent(course, () => []).add(item);
    }
  }

  void _setupRealtimeSubscription() {
    // Подписываемся на изменения в таблице schedule
    _supabase.channel('schedule-updates')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'schedule', // ИСПРАВЛЕНО: было 'schedules'
      callback: (payload) {
        if (mounted) {
          _loadData();
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'schedule', // ИСПРАВЛЕНО: было 'schedules'
      callback: (payload) {
        if (mounted) {
          _loadData();
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'schedule', // ИСПРАВЛЕНО: было 'schedules'
      callback: (payload) {
        if (mounted) {
          _loadData();
        }
      },
    )
        .subscribe();

    // Также подписываемся на detailed_schedules если нужно
    _supabase.channel('detailed-schedule-updates')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'detailed_schedules',
      callback: (payload) {
        if (mounted) {
          _loadData();
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'detailed_schedules',
      callback: (payload) {
        if (mounted) {
          _loadData();
        }
      },
    )
        .subscribe();
  }

  List<Map<String, dynamic>> get _filteredItems {
    final items = _groupedByDay[_selectedDay] ?? [];

    if (_searchQuery.isEmpty && _selectedCourse == 'all') {
      return items;
    }

    return items.where((item) {
      // Фильтр по поиску
      if (_searchQuery.isNotEmpty) {
        final searchLower = _searchQuery.toLowerCase();
        final title = (item['title'] as String? ?? '').toLowerCase();
        final subject = (item['subject'] as String? ?? '').toLowerCase();
        final teacher = (item['teacher_name'] as String? ?? '').toLowerCase();
        final room = (item['room'] as String? ?? '').toLowerCase();

        if (!title.contains(searchLower) &&
            !subject.contains(searchLower) &&
            !teacher.contains(searchLower) &&
            !room.contains(searchLower)) {
          return false;
        }
      }

      // Фильтр по курсу (предмету)
      if (_selectedCourse != 'all') {
        final course = item['subject'] as String? ?? item['title'] as String? ?? '';
        if (course != _selectedCourse) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск по предмету, преподавателю, аудитории...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _viewMode = value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'calendar',
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 20),
                    SizedBox(width: 8),
                    Text('Календарь'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'list',
                child: Row(
                  children: [
                    Icon(Icons.list, size: 20),
                    SizedBox(width: 8),
                    Text('Список'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'week',
                child: Row(
                  children: [
                    Icon(Icons.view_week, size: 20),
                    SizedBox(width: 8),
                    Text('Неделя'),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _viewMode == 'calendar'
                    ? Icons.calendar_today
                    : _viewMode == 'list'
                    ? Icons.list
                    : Icons.view_week,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarView() {
    return Column(
      children: [
        ModernCard(
          child: TableCalendar(
            firstDay: _firstDay,
            lastDay: _lastDay,
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
            },
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Месяц',
              CalendarFormat.week: 'Неделя',
              CalendarFormat.twoWeeks: '2 недели',
            },
            calendarStyle: CalendarStyle(
              selectedDecoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              markersAlignment: Alignment.bottomCenter,
              markersMaxCount: 3,
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
              formatButtonShowsNext: false,
              formatButtonDecoration: BoxDecoration(
                border: Border.all(color: AppColors.primary),
                borderRadius: BorderRadius.circular(8),
              ),
              formatButtonTextStyle: const TextStyle(color: AppColors.primary),
            ),
            eventLoader: (day) {
              return _groupedByDay[day] ?? [];
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildScheduleForSelectedDay(),
      ],
    );
  }

  Widget _buildListView() {
    final courses = _groupedByCourse.keys.toList();

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: courses.length,
      itemBuilder: (context, index) {
        final courseCode = courses[index];
        final courseItems = _groupedByCourse[courseCode]!;
        final courseName = courseCode == 'other' ? 'Другие' : courseCode;
        final filteredItems = courseItems.where((item) {
          if (_searchQuery.isEmpty) return true;
          final searchLower = _searchQuery.toLowerCase();
          final title = (item['title'] as String? ?? '').toLowerCase();
          final subject = (item['subject'] as String? ?? '').toLowerCase();
          final teacher = (item['teacher_name'] as String? ?? '').toLowerCase();
          return title.contains(searchLower) ||
              subject.contains(searchLower) ||
              teacher.contains(searchLower);
        }).toList();

        if (filteredItems.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ModernCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    courseName,
                    style: AppTypography.titleMedium,
                  ),
                ),
                ...filteredItems.map((item) => _buildScheduleItem(item)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekView() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(7, (index) {
              final day = weekStart.add(Duration(days: index));
              final isToday = isSameDay(day, DateTime.now());
              final isSelected = isSameDay(day, _selectedDay);
              final hasEvents = _groupedByDay.containsKey(day);

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedDay = day);
                },
                child: Container(
                  width: 70,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : isToday
                        ? AppColors.primary.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isToday ? AppColors.primary : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat.E('ru_RU').format(day),
                        style: AppTypography.labelSmall.copyWith(
                          color: isSelected ? Colors.white : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.d().format(day),
                        style: AppTypography.titleMedium.copyWith(
                          color: isSelected ? Colors.white : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasEvents) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        _buildScheduleForSelectedDay(),
      ],
    );
  }

  Widget _buildScheduleForSelectedDay() {
    final items = _filteredItems;

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_note,
                size: 64,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Нет занятий на выбранный день',
                style: AppTypography.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Группируем по времени
    items.sort((a, b) {
      final timeA = DateTime.parse(a['start_time'] as String);
      final timeB = DateTime.parse(b['start_time'] as String);
      return timeA.compareTo(timeB);
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            DateFormat('EEEE, d MMMM y', 'ru_RU').format(_selectedDay),
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...items.map((item) => _buildScheduleItem(item)),
      ],
    );
  }

  Widget _buildScheduleItem(Map<String, dynamic> item) {
    final startTime = DateTime.parse(item['start_time'] as String);
    final endTime = DateTime.tryParse(item['end_time'] as String ?? '');
    final title = item['title'] as String? ?? 'Занятие';
    final subject = item['subject'] as String? ?? title;
    final type = item['type'] as String? ?? 'lecture';
    final teacher = item['teacher_name'] as String?;
    final room = item['room'] as String?;
    final groupName = item['group_name'] as String?;
    final dayOfWeek = item['day_of_week'] as String?;

    final isCurrent = DateTime.now().isAfter(startTime) &&
        (endTime == null || DateTime.now().isBefore(endTime));
    final isPast = DateTime.now().isAfter(endTime ?? startTime);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ModernCard(
        onTap: () => _showScheduleDetails(item),
        child: Row(
          children: [
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    DateFormat.Hm().format(startTime),
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (endTime != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      DateFormat.Hm().format(endTime),
                      style: AppTypography.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subject,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrent) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Сейчас',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (title != subject && title.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: AppTypography.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (teacher != null && teacher.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.person,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          teacher,
                          style: AppTypography.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          room ?? 'Аудитория не указана',
                          style: AppTypography.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (groupName != null && groupName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.group,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Группа: $groupName',
                          style: AppTypography.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getTypeColor(type).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getTypeName(type),
                          style: AppTypography.labelSmall.copyWith(
                            color: _getTypeColor(type),
                          ),
                        ),
                      ),
                      if (dayOfWeek != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.gray50.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            dayOfWeek,
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.gray50,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isPast)
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: AppColors.success,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'lecture':
        return AppColors.primary;
      case 'practice':
        return AppColors.secondary;
      case 'lab':
        return AppColors.tertiary;
      case 'exam':
        return AppColors.error;
      case 'seminar':
        return AppColors.success;
      case 'consultation':
        return AppColors.warning;
      default:
        return AppColors.gray50;
    }
  }

  String _getTypeName(String type) {
    switch (type.toLowerCase()) {
      case 'lecture':
        return 'Лекция';
      case 'practice':
        return 'Практика';
      case 'lab':
        return 'Лабораторная';
      case 'exam':
        return 'Экзамен';
      case 'seminar':
        return 'Семинар';
      case 'consultation':
        return 'Консультация';
      default:
        return type;
    }
  }

  void _showScheduleDetails(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ScheduleDetailsModal(item: item),
    );
  }

  Widget _buildCourseFilter() {
    final courses = _groupedByCourse.keys.toList();
    if (courses.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: courses.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              final isSelected = _selectedCourse == 'all';
              return ChoiceChip(
                label: const Text('Все предметы'),
                selected: isSelected,
                onSelected: (_) {
                  setState(() => _selectedCourse = 'all');
                },
                selectedColor: AppColors.primary,
                labelStyle: AppTypography.bodyMedium.copyWith(
                  color: isSelected ? Colors.white : null,
                ),
              );
            }

            final courseCode = courses[index - 1];
            final isSelected = _selectedCourse == courseCode;

            return ChoiceChip(
              label: Text(courseCode == 'other' ? 'Другие' : courseCode),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedCourse = courseCode);
              },
              selectedColor: AppColors.primary,
              labelStyle: AppTypography.bodyMedium.copyWith(
                color: isSelected ? Colors.white : null,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AppScaffold(
      title: 'Расписание',
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() => _selectedDay = DateTime.now());
        },
        child: const Icon(Icons.today),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Повторить',
              onPressed: _loadData,
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: () async {
          setState(() => _refreshing = true);
          await _loadData();
          setState(() => _refreshing = false);
        },
        child: Column(
          children: [
            _buildSearchBar(),
            if (_viewMode == 'list') _buildCourseFilter(),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (_viewMode == 'calendar') _buildCalendarView(),
                  if (_viewMode == 'list') _buildListView(),
                  if (_viewMode == 'week') _buildWeekView(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleDetailsModal extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ScheduleDetailsModal({required this.item});

  @override
  Widget build(BuildContext context) {
    final startTime = DateTime.parse(item['start_time'] as String);
    final endTime = DateTime.tryParse(item['end_time'] as String ?? '');
    final title = item['title'] as String? ?? 'Занятие';
    final subject = item['subject'] as String? ?? title;
    final teacher = item['teacher_name'] as String?;
    final room = item['room'] as String?;
    final type = item['type'] as String?;
    final groupName = item['group_name'] as String?;
    final dayOfWeek = item['day_of_week'] as String?;
    final semester = item['semester'] as int?;
    final academicYear = item['academic_year'] as int?;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
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
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject, style: AppTypography.titleLarge),
                if (title != subject && title.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _buildDetailRow(
                  context,
                  'Время',
                  '${DateFormat.Hm().format(startTime)}'
                      '${endTime != null ? ' - ${DateFormat.Hm().format(endTime)}' : ''}',
                ),
                if (dayOfWeek != null)
                  _buildDetailRow(context, 'День недели', dayOfWeek),
                if (teacher != null) _buildDetailRow(context, 'Преподаватель', teacher),
                if (room != null) _buildDetailRow(context, 'Аудитория', room),
                if (type != null) _buildDetailRow(context, 'Тип', _getTypeName(type)),
                if (groupName != null) _buildDetailRow(context, 'Группа', groupName),
                if (semester != null) _buildDetailRow(context, 'Семестр', semester.toString()),
                if (academicYear != null) _buildDetailRow(context, 'Учебный год', academicYear.toString()),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Закрыть'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Добавить в календарь',
                        onPressed: () {
                          // TODO: Реализовать добавление в календарь устройства
                          Navigator.pop(context);
                          context.showSnackBar('Добавлено в календарь');
                        },
                        icon: Icons.calendar_today,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _getTypeName(String type) {
    switch (type.toLowerCase()) {
      case 'lecture':
        return 'Лекция';
      case 'practice':
        return 'Практика';
      case 'lab':
        return 'Лабораторная';
      case 'exam':
        return 'Экзамен';
      case 'seminar':
        return 'Семинар';
      case 'consultation':
        return 'Консультация';
      default:
        return type;
    }
  }
}