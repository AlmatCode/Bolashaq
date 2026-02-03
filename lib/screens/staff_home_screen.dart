import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../core/theme.dart';
import 'login_screen.dart';

class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final SupabaseClient _supabase = Supabase.instance.client;
  late TabController _fractionTabController;
  RealtimeChannel? _realtimeChannel;

  // Данные сотрудника
  String? _staffId;
  String? _staffName;
  List<StaffFraction> _allFractions = [];
  List<StaffFraction> _staffFractions = [];

  // Заявки по фракциям
  Map<String, List<FractionApplication>> _fractionApplications = {};
  Map<String, bool> _fractionLoading = {};
  Map<String, String> _fractionFilters = {};
  Map<String, List<FractionMember>> _fractionMembers = {};
  Map<String, Map<String, FractionAttendanceRecord>> _fractionAttendance = {};
  DateTime _selectedDate = DateTime.now();

  // Статистика
  Map<String, int> _stats = {
    'total_applications': 0,
    'pending': 0,
    'approved': 0,
    'rejected': 0,
  };

  // Режим просмотра
  bool _showOnlyMyFractions = false;

  // Фильтр по типу (кружки или клубы)
  String _typeFilter = 'all'; // 'all', 'circle', 'club'

  // Для управления внутренними табами (заявки/посещаемость)
  final Map<String, TabController> _innerTabControllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Инициализируем TabController с минимальной длиной (будет обновлен после загрузки данных)
    _fractionTabController = TabController(
      length: 0, // Временно 0, обновим после загрузки данных
      vsync: this,
    );

    _loadStaffData();
    _setupRealtimeSubscription();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCurrentData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeChannel?.unsubscribe();
    _fractionTabController.dispose();

    // Dispose всех внутренних контроллеров
    for (var controller in _innerTabControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _setupRealtimeSubscription() {
    _realtimeChannel = _supabase
        .channel('staff_updates')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'section_applications',
      callback: (payload) {
        if (mounted) {
          _refreshCurrentData();
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'attendance_records',
      callback: (payload) {
        if (mounted) {
          final sectionId = payload.newRecord?['section_id']?.toString();
          if (sectionId != null && _fractionAttendance.containsKey(sectionId)) {
            final members = _fractionMembers[sectionId] ?? [];
            _loadFractionAttendance(sectionId, members);
          }
        }
      },
    )
        .subscribe();
  }

  Future<void> _refreshCurrentData() async {
    if (_staffFractions.isNotEmpty && _fractionTabController.index < _staffFractions.length) {
      final fractionId = _staffFractions[_fractionTabController.index].id;
      await _loadFractionApplications(fractionId);
      await _loadFractionMembers(fractionId);
    }
  }

  Future<void> _loadStaffData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      _staffId = user.id;

      // Получаем имя сотрудника из профиля
      final profileResponse = await _supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .single()
          .catchError((e) => null);

      if (profileResponse != null) {
        _staffName = profileResponse['full_name'] as String? ?? 'Сотрудник';
      }

      // Загружаем ВСЕ фракции (type='club' и type='circle')
      final sectionsResponse = await _supabase
          .from('extended_sections')
          .select('''
            id, title, type, category, coach_name, coach_id,
            schedule, location, capacity, current_members,
            is_active, registration_open, description
          ''')
          .inFilter('type', ['circle', 'club'])
          .order('title');

      if (sectionsResponse != null && sectionsResponse.isNotEmpty) {
        final List<StaffFraction> allFractions = sectionsResponse
            .map((section) =>
            StaffFraction.fromJson(Map<String, dynamic>.from(section)))
            .toList();

        setState(() {
          _allFractions = allFractions;
          _staffFractions = _getFilteredFractions(allFractions);
        });

        // Инициализируем состояние для каждой фракции
        for (var fraction in _staffFractions) {
          _fractionFilters[fraction.id] = 'pending';
          _fractionLoading[fraction.id] = false;
        }

        // Обновляем TabController с новым количеством вкладок
        final oldControllerIndex = _fractionTabController.index;
        _fractionTabController.dispose();
        _fractionTabController = TabController(
          length: _staffFractions.length,
          vsync: this,
          initialIndex: oldControllerIndex < _staffFractions.length ? oldControllerIndex : 0,
        );

        // Добавляем listener для загрузки данных при переключении вкладок
        _fractionTabController.addListener(() {
          if (!_fractionTabController.indexIsChanging && _staffFractions.isNotEmpty) {
            final fractionId = _staffFractions[_fractionTabController.index].id;
            _loadFractionApplications(fractionId);
            _loadFractionMembers(fractionId);
          }
        });

        // Загружаем заявки для первой вкладки
        if (_staffFractions.isNotEmpty) {
          await _loadFractionApplications(_staffFractions.first.id);
          await _loadFractionMembers(_staffFractions.first.id);
        }
      }
    } catch (error) {
      debugPrint('Error loading staff data: $error');
      _showSnackBar('Ошибка загрузки данных', isError: true);
    }
  }

  List<StaffFraction> _getFilteredFractions(List<StaffFraction> allFractions) {
    List<StaffFraction> filtered = allFractions;

    // Отладочная информация
    print('=== Filtering Fractions ===');
    print('Type filter: $_typeFilter');
    print('Show only my fractions: $_showOnlyMyFractions');
    print('Total fractions before filter: ${filtered.length}');

    // Применяем фильтр по типу
    if (_typeFilter != 'all') {
      filtered = filtered.where((fraction) => fraction.type == _typeFilter).toList();
      print('After type filter ($_typeFilter): ${filtered.length}');
      print('Filtered types: ${filtered.map((f) => f.type).toList()}');
    }

    // Применяем фильтр "только мои фракции"
    if (_showOnlyMyFractions) {
      filtered = filtered.where((fraction) =>
      fraction.coachId == _staffId ||
          fraction.coachName == _staffName).toList();
      print('After "my fractions" filter: ${filtered.length}');
    }

    print('Total fractions after filter: ${filtered.length}');
    return filtered;
  }

  Future<void> _updateTypeFilter(String type) async {
    // Сохраняем текущий ID фракции для восстановления позиции
    String? currentFractionId;
    if (_staffFractions.isNotEmpty && _fractionTabController.index < _staffFractions.length) {
      currentFractionId = _staffFractions[_fractionTabController.index].id;
    }

    setState(() {
      _typeFilter = type;
      // Пересчитываем отфильтрованные фракции
      _staffFractions = _getFilteredFractions(_allFractions);
    });

    // Пересоздаем TabController с новым количеством вкладок
    final oldControllerIndex = _fractionTabController.index;
    _fractionTabController.dispose();
    _fractionTabController = TabController(
      length: _staffFractions.length,
      vsync: this,
      initialIndex: oldControllerIndex < _staffFractions.length ? oldControllerIndex : 0,
    );

    // Восстанавливаем позицию, если возможно
    if (currentFractionId != null && _staffFractions.isNotEmpty) {
      final newIndex = _staffFractions.indexWhere((f) => f.id == currentFractionId);
      if (newIndex != -1 && newIndex < _staffFractions.length) {
        _fractionTabController.index = newIndex;
      }
    }

    // Добавляем listener для нового контроллера
    _fractionTabController.addListener(() {
      if (!_fractionTabController.indexIsChanging && _staffFractions.isNotEmpty) {
        final fractionId = _staffFractions[_fractionTabController.index].id;
        _loadFractionApplications(fractionId);
        _loadFractionMembers(fractionId);
      }
    });

    // Загружаем данные для текущей вкладки
    if (_staffFractions.isNotEmpty) {
      final currentIndex = _fractionTabController.index;
      if (currentIndex < _staffFractions.length) {
        await _loadFractionApplications(_staffFractions[currentIndex].id);
        await _loadFractionMembers(_staffFractions[currentIndex].id);
      } else {
        await _loadFractionApplications(_staffFractions.first.id);
        await _loadFractionMembers(_staffFractions.first.id);
      }
    }
  }

  Future<void> _toggleViewMode() async {
    // Сохраняем текущий ID фракции для восстановления позиции
    String? currentFractionId;
    if (_staffFractions.isNotEmpty && _fractionTabController.index < _staffFractions.length) {
      currentFractionId = _staffFractions[_fractionTabController.index].id;
    }

    setState(() {
      _showOnlyMyFractions = !_showOnlyMyFractions;
      // Пересчитываем отфильтрованные фракции с учетом обоих фильтров
      _staffFractions = _getFilteredFractions(_allFractions);
    });

    // Пересоздаем TabController с новым количеством вкладок
    final oldControllerIndex = _fractionTabController.index;
    _fractionTabController.dispose();
    _fractionTabController = TabController(
      length: _staffFractions.length,
      vsync: this,
      initialIndex: oldControllerIndex < _staffFractions.length ? oldControllerIndex : 0,
    );

    // Восстанавливаем позицию, если возможно
    if (currentFractionId != null && _staffFractions.isNotEmpty) {
      final newIndex = _staffFractions.indexWhere((f) => f.id == currentFractionId);
      if (newIndex != -1 && newIndex < _staffFractions.length) {
        _fractionTabController.index = newIndex;
      }
    }

    // Добавляем listener для нового контроллера
    _fractionTabController.addListener(() {
      if (!_fractionTabController.indexIsChanging && _staffFractions.isNotEmpty) {
        final fractionId = _staffFractions[_fractionTabController.index].id;
        _loadFractionApplications(fractionId);
        _loadFractionMembers(fractionId);
      }
    });

    // Загружаем данные для текущей вкладки
    if (_staffFractions.isNotEmpty) {
      final currentIndex = _fractionTabController.index;
      if (currentIndex < _staffFractions.length) {
        await _loadFractionApplications(_staffFractions[currentIndex].id);
        await _loadFractionMembers(_staffFractions[currentIndex].id);
      } else {
        await _loadFractionApplications(_staffFractions.first.id);
        await _loadFractionMembers(_staffFractions.first.id);
      }
    }
  }

  Future<void> _loadFractionApplications(String fractionId) async {
    try {
      setState(() => _fractionLoading[fractionId] = true);

      final applicationsResponse = await _supabase
          .from('section_applications')
          .select('''
            *,
            profiles:applicant_id(full_name, email, student_group, avatar_url, phone),
            extended_sections:section_id(title, type, category, schedule, location)
          ''')
          .eq('section_id', fractionId)
          .order('applied_at', ascending: false);

      if (applicationsResponse != null) {
        final List<FractionApplication> applications = [];
        int total = 0, pending = 0, approved = 0, rejected = 0;

        for (var app in applicationsResponse) {
          try {
            final application =
            FractionApplication.fromJson(Map<String, dynamic>.from(app));
            applications.add(application);

            total++;
            switch (application.status) {
              case 'pending':
                pending++;
                break;
              case 'approved':
                approved++;
                break;
              case 'rejected':
                rejected++;
                break;
            }
          } catch (e) {
            debugPrint('Error parsing application: $e');
          }
        }

        setState(() {
          _fractionApplications[fractionId] = applications;
          _fractionLoading[fractionId] = false;
          _stats = {
            'total_applications': total,
            'pending': pending,
            'approved': approved,
            'rejected': rejected,
          };
        });
      }
    } catch (error) {
      debugPrint('Error loading applications: $error');
      setState(() => _fractionLoading[fractionId] = false);
      _showSnackBar('Ошибка загрузки заявок', isError: true);
    }
  }

  Future<void> _loadFractionMembers(String fractionId) async {
    try {
      final membersResponse = await _supabase
          .from('user_sections')
          .select('''
            id, user_id, joined_at, role,
            profiles!inner(full_name, email, student_group, avatar_url, phone)
          ''')
          .eq('section_id', fractionId)
          .eq('role', 'member')
          .order('full_name', referencedTable: 'profiles');

      if (membersResponse != null) {
        final List<FractionMember> members = [];
        for (var member in membersResponse) {
          members.add(FractionMember.fromJson(Map<String, dynamic>.from(member)));
        }

        setState(() {
          _fractionMembers[fractionId] = members;
        });

        // Загружаем посещаемость для этих участников
        await _loadFractionAttendance(fractionId, members);
      }
    } catch (error) {
      debugPrint('Error loading fraction members: $error');
    }
  }

  Future<void> _loadFractionAttendance(
      String fractionId, List<FractionMember> members) async {
    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final attendanceResponse = await _supabase
          .from('attendance_records')
          .select('*')
          .eq('section_id', fractionId)
          .eq('date', formattedDate);

      Map<String, FractionAttendanceRecord> attendanceMap = {};

      if (attendanceResponse != null) {
        for (var record in attendanceResponse) {
          final attendance = FractionAttendanceRecord.fromJson(
              Map<String, dynamic>.from(record));
          attendanceMap[attendance.userId] = attendance;
        }
      }

      // Создаем пустые записи для тех, у кого нет посещаемости
      for (var member in members) {
        if (!attendanceMap.containsKey(member.userId)) {
          attendanceMap[member.userId] = FractionAttendanceRecord(
            id: '',
            sectionId: fractionId,
            userId: member.userId,
            date: _selectedDate,
            status: AttendanceStatus.absent,
            notes: '',
            recordedBy: _staffId,
            recordedAt: DateTime.now(),
          );
        }
      }

      setState(() {
        _fractionAttendance[fractionId] = attendanceMap;
      });
    } catch (error) {
      debugPrint('Error loading attendance: $error');
    }
  }

  Future<void> _updateApplicationStatus(
      String applicationId,
      String newStatus,
      String fractionId,
      String applicantId,
      ) async {
    try {
      await _supabase.from('section_applications').update({
        'status': newStatus,
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': _staffId,
        'reviewer_name': _staffName,
      }).eq('id', applicationId);

      if (newStatus == 'approved') {
        await _increaseFractionMembers(fractionId);
        await _addStudentToFraction(fractionId, applicantId);
      }

      await _refreshCurrentData();
      _showSnackBar('Статус заявки изменен');
    } catch (error) {
      debugPrint('Error updating application status: $error');
      _showSnackBar('Ошибка обновления статуса', isError: true);
    }
  }

  Future<void> _updateAttendance(
      String fractionId, String userId, AttendanceStatus status) async {
    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final existingRecord = _fractionAttendance[fractionId]?[userId];

      if (existingRecord != null && existingRecord.id.isNotEmpty) {
        await _supabase.from('attendance_records').update({
          'status': status.name,
          'recorded_by': _staffId,
          'recorded_at': DateTime.now().toIso8601String(),
        }).eq('id', existingRecord.id);
      } else {
        final response = await _supabase.from('attendance_records').insert({
          'section_id': fractionId,
          'user_id': userId,
          'date': formattedDate,
          'status': status.name,
          'recorded_by': _staffId,
          'recorded_at': DateTime.now().toIso8601String(),
        }).select('id');

        if (response != null && response.isNotEmpty) {
          final newId = response[0]['id'].toString();
          setState(() {
            _fractionAttendance[fractionId]?[userId] = FractionAttendanceRecord(
              id: newId,
              sectionId: fractionId,
              userId: userId,
              date: _selectedDate,
              status: status,
              notes: '',
              recordedBy: _staffId,
              recordedAt: DateTime.now(),
            );
          });
        }
      }

      // Обновляем локальное состояние
      setState(() {
        final record = _fractionAttendance[fractionId]?[userId];
        if (record != null) {
          _fractionAttendance[fractionId]?[userId] = FractionAttendanceRecord(
            id: record.id,
            sectionId: record.sectionId,
            userId: record.userId,
            date: record.date,
            status: status,
            notes: record.notes,
            recordedBy: _staffId,
            recordedAt: DateTime.now(),
          );
        }
      });

      _showSnackBar('Посещаемость обновлена');
    } catch (error) {
      debugPrint('Error updating attendance: $error');
      _showSnackBar('Ошибка обновления посещаемости', isError: true);
    }
  }

  Future<void> _saveAllAttendance(String fractionId) async {
    try {
      final attendanceRecords = _fractionAttendance[fractionId] ?? {};
      final List<Map<String, dynamic>> recordsToInsert = [];
      final List<Map<String, dynamic>> recordsToUpdate = [];

      for (var record in attendanceRecords.values) {
        final formattedDate = DateFormat('yyyy-MM-dd').format(record.date);

        final recordData = {
          'section_id': record.sectionId,
          'user_id': record.userId,
          'date': formattedDate,
          'status': record.status.name,
          'recorded_by': _staffId,
          'recorded_at': DateTime.now().toIso8601String(),
        };

        if (record.id.isEmpty) {
          recordsToInsert.add(recordData);
        } else {
          recordsToUpdate.add({
            'id': record.id,
            ...recordData,
          });
        }
      }

      // Вставляем новые записи
      if (recordsToInsert.isNotEmpty) {
        await _supabase.from('attendance_records').insert(recordsToInsert);
      }

      // Обновляем существующие записи
      for (var record in recordsToUpdate) {
        await _supabase.from('attendance_records')
            .update(record)
            .eq('id', record['id']);
      }

      _showSnackBar('Посещаемость сохранена');
    } catch (error) {
      debugPrint('Error saving all attendance: $error');
      _showSnackBar('Ошибка сохранения посещаемости', isError: true);
    }
  }

  Future<void> _generateAttendanceReport(String fractionId) async {
    try {
      final fraction = _staffFractions.firstWhere((f) => f.id == fractionId);
      final members = _fractionMembers[fractionId] ?? [];
      final attendance = _fractionAttendance[fractionId] ?? {};

      if (members.isEmpty) {
        _showSnackBar('Нет участников для отчета', isError: true);
        return;
      }

      final List<List<dynamic>> reportData = [];

      // Заголовки
      reportData.add([
        'ФИО студента',
        'Группа',
        'Кружок/Клуб',
        'Дата',
        'Посещение'
      ]);

      // Данные
      for (var member in members) {
        final record = attendance[member.userId];
        final attendanceStatus = record?.status ?? AttendanceStatus.absent;

        reportData.add([
          member.fullName,
          member.studentGroup,
          fraction.title,
          DateFormat('dd.MM.yyyy').format(_selectedDate),
          attendanceStatus.displayName
        ]);
      }

      // Создаем CSV
      final csvData = reportData.map((row) =>
          row.map((cell) => '"$cell"').join(',')
      ).join('\n');

      // Копируем в буфер обмена
      await Clipboard.setData(ClipboardData(text: csvData));

      _showSnackBar('Отчет скопирован в буфер обмена');

      // Показываем диалог с отчетом
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Отчет посещаемости'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_getTypeLabel(fraction.type)}: ${fraction.title}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Дата: ${DateFormat('dd.MM.yyyy').format(_selectedDate)}'),
                const SizedBox(height: 16),
                ...members.map((member) {
                  final record = attendance[member.userId];
                  final status = record?.status ?? AttendanceStatus.absent;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            member.fullName,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getAttendanceColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _getAttendanceColor(status).withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            status.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              color: _getAttendanceColor(status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();

                // Экспорт в текстовый файл
                final String reportText = '''
Отчет посещаемости
${_getTypeLabel(fraction.type)}: ${fraction.title}
Дата: ${DateFormat('dd.MM.yyyy').format(_selectedDate)}
Руководитель: ${fraction.coachName}

${members.map((member) {
                  final record = attendance[member.userId];
                  final status = record?.status ?? AttendanceStatus.absent;
                  return '${member.fullName} (${member.studentGroup}) - ${status.displayName}';
                }).join('\n')}

Итого: ${members.length} участников
Присутствовали: ${attendance.values.where((a) => a.status == AttendanceStatus.present).length}
Отсутствовали: ${attendance.values.where((a) => a.status == AttendanceStatus.absent).length}
По уважительной причине: ${attendance.values.where((a) => a.status == AttendanceStatus.excused).length}
''';

                await Clipboard.setData(ClipboardData(text: reportText));
                _showSnackBar('Отчет сохранен в буфер обмена');
              },
              child: const Text('Экспорт'),
            ),
          ],
        ),
      );

    } catch (error) {
      debugPrint('Error generating report: $error');
      _showSnackBar('Ошибка создания отчета', isError: true);
    }
  }

  Future<void> _increaseFractionMembers(String fractionId) async {
    try {
      final fractionResponse = await _supabase
          .from('extended_sections')
          .select('current_members, capacity')
          .eq('id', fractionId)
          .single();

      final currentMembers = _toInt(fractionResponse['current_members']);
      final capacity = _toInt(fractionResponse['capacity']);

      if (capacity > 0 && currentMembers >= capacity) {
        throw Exception('${_getTypeLabel(fractionResponse['type'])} заполнен');
      }

      await _supabase.from('extended_sections').update({
        'current_members': currentMembers + 1,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', fractionId);
    } catch (error) {
      debugPrint('Error increasing fraction members: $error');
      rethrow;
    }
  }

  Future<void> _addStudentToFraction(String fractionId, String studentId) async {
    try {
      final existing = await _supabase
          .from('user_sections')
          .select('id')
          .eq('user_id', studentId)
          .eq('section_id', fractionId)
          .maybeSingle();

      if (existing == null) {
        await _supabase.from('user_sections').insert({
          'user_id': studentId,
          'section_id': fractionId,
          'joined_at': DateTime.now().toIso8601String(),
          'role': 'member',
          'added_by': _staffId,
          'added_by_name': _staffName,
        });
      }
    } catch (error) {
      debugPrint('Error adding student to fraction: $error');
    }
  }

  Future<void> _showDatePicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });

      // Обновляем посещаемость для всех фракций
      for (var fraction in _staffFractions) {
        final members = _fractionMembers[fraction.id];
        if (members != null) {
          await _loadFractionAttendance(fraction.id, members);
        }
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showApplicationDetails(FractionApplication application) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Заявка #${application.shortId}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Студент:', application.studentName),
              _buildDetailRow('Группа:', application.studentGroup),
              _buildDetailRow('Email:', application.studentEmail),
              const SizedBox(height: 16),
              _buildDetailRow(_getTypeLabel(application.sectionType) + ':', application.sectionTitle),
              if (application.sectionSchedule.isNotEmpty)
                _buildDetailRow('Расписание:', application.sectionSchedule),
              if (application.sectionLocation.isNotEmpty)
                _buildDetailRow('Место:', application.sectionLocation),
              const SizedBox(height: 16),
              _buildDetailRow(
                'Дата подачи:',
                DateFormat('dd.MM.yyyy HH:mm').format(application.appliedAt),
              ),
              _buildDetailRow('Статус:', _getStatusLabel(application.status)),
              if (application.motivation.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Мотивация:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  application.motivation,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
          if (application.status == 'pending') ...[
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showRejectDialog(application);
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.error),
              ),
              child: Text(
                'Отклонить',
                style: TextStyle(color: AppColors.error),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateApplicationStatus(
                  application.id,
                  'approved',
                  application.sectionId,
                  application.applicantId,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
              child: const Text('Принять'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRejectDialog(FractionApplication application) async {
    final TextEditingController reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отклонить заявку'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Укажите причину отказа (необязательно):'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Причина отказа...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              Navigator.of(context).pop();

              _updateApplicationStatusWithReason(
                application.id,
                'rejected',
                application.sectionId,
                application.applicantId,
                reason,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateApplicationStatusWithReason(
      String applicationId,
      String newStatus,
      String fractionId,
      String applicantId,
      String reason,
      ) async {
    try {
      await _supabase.from('section_applications').update({
        'status': newStatus,
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': _staffId,
        'reviewer_name': _staffName,
        'review_notes': reason.isNotEmpty ? reason : null,
      }).eq('id', applicationId);

      if (_staffFractions.isNotEmpty && _fractionTabController.index < _staffFractions.length) {
        final currentFractionId = _staffFractions[_fractionTabController.index].id;
        await _loadFractionApplications(currentFractionId);
      }

      _showSnackBar('Заявка отклонена');
    } catch (error) {
      debugPrint('Error rejecting application: $error');
      _showSnackBar('Ошибка при отклонении заявки', isError: true);
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();

      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
        );
      }
    } catch (error) {
      debugPrint('Error signing out: $error');
      _showSnackBar('Ошибка при выходе из системы', isError: true);
    }
  }

  Future<void> _showSignOutDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _signOut();
            },
            child: const Text(
              'Выйти',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
            ),
          ],
        )
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'На рассмотрении';
      case 'approved':
        return 'Принята';
      case 'rejected':
        return 'Отклонена';
      case 'cancelled':
        return 'Отменена';
      default:
        return status;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'circle':
        return 'Кружок';
      case 'club':
        return 'Клуб';
      default:
        return 'Секция';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Color _getAttendanceColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return AppColors.success;
      case AttendanceStatus.absent:
        return AppColors.error;
      case AttendanceStatus.excused:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  Widget _buildStatistics() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Всего', _stats['total_applications']?.toString() ?? '0',
              Icons.list_alt, AppColors.primary),
          _buildStatItem('Ожидают', _stats['pending']?.toString() ?? '0',
              Icons.pending, Colors.orange),
          _buildStatItem('Приняты', _stats['approved']?.toString() ?? '0',
              Icons.check_circle, AppColors.success),
          _buildStatItem('Отклонены', _stats['rejected']?.toString() ?? '0',
              Icons.cancel, AppColors.error),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: Text('Все', style: TextStyle(fontFamily: 'Roboto')),
              selected: _typeFilter == 'all',
              onSelected: (selected) {
                if (selected) {
                  _updateTypeFilter('all');
                }
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('Кружки', style: TextStyle(fontFamily: 'Roboto')),
              selected: _typeFilter == 'circle',
              onSelected: (selected) {
                if (selected) {
                  _updateTypeFilter('circle');
                }
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('Клубы', style: TextStyle(fontFamily: 'Roboto')),
              selected: _typeFilter == 'club',
              onSelected: (selected) {
                if (selected) {
                  _updateTypeFilter('club');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(icon, size: 20, color: color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceTab(String fractionId) {
    final members = _fractionMembers[fractionId] ?? [];
    final attendance = _fractionAttendance[fractionId] ?? {};
    final fraction = _staffFractions.firstWhere(
          (f) => f.id == fractionId,
      orElse: () => StaffFraction(
        id: '',
        title: '',
        type: '',
        category: '',
        coachName: '',
        coachId: '',
        schedule: '',
        location: '',
        capacity: 0,
        currentMembers: 0,
        isActive: false,
        registrationOpen: false,
        description: '',
      ),
    );

    if (members.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group,
              size: 80,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'В ${_getTypeLabel(fraction.type).toLowerCase()} нет участников',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Информация о кружке/клубе
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    fraction.type == 'circle' ? Icons.music_note : Icons.flag,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fraction.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getTypeLabel(fraction.type),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (fraction.schedule.isNotEmpty)
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        fraction.schedule,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              if (fraction.location.isNotEmpty)
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      fraction.location,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Заголовок с датой
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Посещаемость за:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _showDatePicker,
                child: Row(
                  children: [
                    Text(
                      DateFormat('dd.MM.yyyy').format(_selectedDate),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.edit_calendar,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Кнопки управления
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _saveAllAttendance(fractionId),
                  icon: const Icon(Icons.save, size: 20),
                  label: const Text('Сохранить все'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _generateAttendanceReport(fractionId),
                  icon: const Icon(Icons.download, size: 20),
                  label: const Text('Отчет'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Статистика посещаемости
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAttendanceStat(
                'Присутствовали',
                attendance.values
                    .where((a) => a.status == AttendanceStatus.present)
                    .length,
                AppColors.success,
              ),
              _buildAttendanceStat(
                'Отсутствовали',
                attendance.values
                    .where((a) => a.status == AttendanceStatus.absent)
                    .length,
                AppColors.error,
              ),
              _buildAttendanceStat(
                'По ув. причине',
                attendance.values
                    .where((a) => a.status == AttendanceStatus.excused)
                    .length,
                Colors.orange,
              ),
            ],
          ),
        ),

        // Список участников
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              final record = attendance[member.userId];
              return _buildAttendanceCard(member, record, fractionId);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceStat(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAttendanceCard(
      FractionMember member, FractionAttendanceRecord? record, String fractionId) {
    final status = record?.status ?? AttendanceStatus.absent;
    final isPresent = status == AttendanceStatus.present;
    final isExcused = status == AttendanceStatus.excused;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Аватар и информация
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                      image: member.avatarUrl != null
                          ? DecorationImage(
                        image: NetworkImage(member.avatarUrl!),
                        fit: BoxFit.cover,
                      )
                          : null,
                    ),
                    child: member.avatarUrl == null
                        ? Icon(
                      Icons.person,
                      color: AppColors.primary,
                      size: 24,
                    )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          member.studentGroup,
                          style: TextStyle(
                            fontSize: 14,
                            color:
                            Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        if (member.email.isNotEmpty)
                          Text(
                            member.email,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                              Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Текущий статус
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getAttendanceColor(status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getAttendanceColor(status).withOpacity(0.3),
                ),
              ),
              child: Text(
                status.displayName,
                style: TextStyle(
                  fontSize: 12,
                  color: _getAttendanceColor(status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Кнопки статуса
            Row(
              children: [
                // Присутствовал
                IconButton(
                  onPressed: () => _updateAttendance(
                    fractionId,
                    member.userId,
                    AttendanceStatus.present,
                  ),
                  icon: Icon(
                    Icons.check_circle,
                    color: isPresent
                        ? AppColors.success
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  ),
                  tooltip: 'Присутствовал',
                ),

                // Отсутствовал
                IconButton(
                  onPressed: () => _updateAttendance(
                    fractionId,
                    member.userId,
                    AttendanceStatus.absent,
                  ),
                  icon: Icon(
                    Icons.cancel,
                    color: !isPresent && !isExcused
                        ? AppColors.error
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  ),
                  tooltip: 'Отсутствовал',
                ),

                // По уважительной причине
                IconButton(
                  onPressed: () => _updateAttendance(
                    fractionId,
                    member.userId,
                    AttendanceStatus.excused,
                  ),
                  icon: Icon(
                    Icons.medical_services,
                    color: isExcused
                        ? Colors.orange
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  ),
                  tooltip: 'По уважительной причине',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(String currentFilter, Function(String) onFilterChanged) {
    final filters = <Map<String, Object>>[
      {'value': 'pending', 'label': 'Ожидают', 'color': Colors.orange},
      {'value': 'approved', 'label': 'Приняты', 'color': AppColors.success},
      {'value': 'rejected', 'label': 'Отклонены', 'color': AppColors.error},
      {'value': 'all', 'label': 'Все', 'color': AppColors.primary},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: filters.map((filter) {
          final value = filter['value'] as String;
          final label = filter['label'] as String;
          final color = filter['color'] as Color;
          final isSelected = currentFilter == value;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) => onFilterChanged(value),
              backgroundColor: isSelected
                  ? color.withOpacity(0.1)
                  : Theme.of(context).colorScheme.surfaceVariant,
              selectedColor: color.withOpacity(0.2),
              checkmarkColor: color,
              labelStyle: TextStyle(
                color: isSelected
                    ? color
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? color : Theme.of(context).dividerColor,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildApplicationCard(FractionApplication application) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => _showApplicationDetails(application),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Аватар студента
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                      image: application.studentAvatar != null
                          ? DecorationImage(
                        image: NetworkImage(application.studentAvatar!),
                        fit: BoxFit.cover,
                      )
                          : null,
                    ),
                    child: application.studentAvatar == null
                        ? Icon(
                      Icons.person,
                      color: AppColors.primary,
                      size: 24,
                    )
                        : null,
                  ),
                  const SizedBox(width: 12),

                  // Информация о студенте
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          application.studentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        if (application.studentGroup.isNotEmpty)
                          Text(
                            application.studentGroup,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Статус
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(application.status)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getStatusColor(application.status)
                            .withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(application.status),
                          size: 12,
                          color: _getStatusColor(application.status),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getStatusLabel(application.status),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(application.status),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Информация о кружке/клубе
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            application.sectionTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getTypeLabel(application.sectionType),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          application.sectionType == 'circle'
                              ? Icons.music_note
                              : Icons.flag,
                          size: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getTypeLabel(application.sectionType),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                        ),
                        const Spacer(),
                        if (application.sectionSchedule.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.5),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                application.sectionSchedule,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Кнопки действий
              if (application.status == 'pending')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showRejectDialog(application),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.error),
                        ),
                        child: Text(
                          'Отклонить',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _updateApplicationStatus(
                          application.id,
                          'approved',
                          application.sectionId,
                          application.applicantId,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                        child: const Text('Принять'),
                      ),
                    ),
                  ],
                )
              else if (application.status == 'approved')
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Студент принят',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (application.status == 'rejected')
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cancel,
                            size: 16,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Заявка отклонена',
                            style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

              const SizedBox(height: 8),

              // Дата подачи
              Text(
                DateFormat('dd.MM.yyyy HH:mm').format(application.appliedAt),
                style: TextStyle(
                  fontSize: 12,
                  color:
                  Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApplicationsTab(String fractionId) {
    final applications = _fractionApplications[fractionId] ?? [];
    final currentFilter = _fractionFilters[fractionId] ?? 'pending';
    final isLoading = _fractionLoading[fractionId] ?? false;

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    List<FractionApplication> filteredApplications = applications;
    if (currentFilter != 'all') {
      filteredApplications =
          applications.where((app) => app.status == currentFilter).toList();
    }

    if (filteredApplications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flag,
              size: 80,
              color:
              Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              currentFilter == 'all'
                  ? 'Нет заявок'
                  : 'Нет заявок со статусом "${_getStatusLabel(
                  currentFilter)}"',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFractionApplications(fractionId),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: filteredApplications.length,
        itemBuilder: (context, index) {
          return _buildApplicationCard(filteredApplications[index]);
        },
      ),
    );
  }

  Widget _buildFractionContent(StaffFraction fraction) {
    // Создаем или получаем контроллер для внутренних вкладок этой фракции
    if (!_innerTabControllers.containsKey(fraction.id)) {
      _innerTabControllers[fraction.id] = TabController(
        length: 2,
        vsync: this,
      );
    }

    final innerTabController = _innerTabControllers[fraction.id]!;

    return Column(
      children: [
        // Внутренние табы для заявок и посещаемости
        Container(
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: TabBar(
            controller: innerTabController,
            tabs: const [
              Tab(icon: Icon(Icons.list_alt), text: 'Заявки'),
              Tab(icon: Icon(Icons.group), text: 'Посещаемость'),
            ],
          ),
        ),

        // Контент внутренних вкладок
        Expanded(
          child: TabBarView(
            controller: innerTabController,
            children: [
              // Вкладка заявок
              Column(
                children: [
                  // Фильтры
                  _buildFilterChips(
                    _fractionFilters[fraction.id] ?? 'pending',
                        (filter) => setState(() {
                      _fractionFilters[fraction.id] = filter;
                    }),
                  ),
                  Expanded(
                    child: _buildApplicationsTab(fraction.id),
                  ),
                ],
              ),
              // Вкладка посещаемости
              _buildAttendanceTab(fraction.id),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_allFractions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Панель сотрудника'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadStaffData,
              tooltip: 'Обновить',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _showSignOutDialog,
              tooltip: 'Выйти',
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.flag,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                'Кружки и клубы не найдены',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadStaffData,
                child: const Text('Обновить'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Панель сотрудника'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              // Фильтр по типу
              _buildTypeFilter(),

              // Табы фракций
              TabBar(
                controller: _fractionTabController,
                isScrollable: true,
                tabs: _staffFractions
                    .map((fraction) => Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: fraction.type == 'circle'
                              ? AppColors.success
                              : AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        fraction.title.length > 12
                            ? '${fraction.title.substring(0, 12)}...'
                            : fraction.title,
                      ),
                      if (fraction.coachId == _staffId ||
                          fraction.coachName == _staffName)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.person, size: 12),
                        ),
                    ],
                  ),
                ))
                    .toList(),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_showOnlyMyFractions
                ? Icons.filter_list
                : Icons.filter_list_off),
            onPressed: _toggleViewMode,
            tooltip: _showOnlyMyFractions
                ? 'Показать все кружки и клубы'
                : 'Показать только мои кружки и клубы',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCurrentData,
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _showSignOutDialog,
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: Column(
        children: [
          // Статистика
          _buildStatistics(),

          // Контент с вкладками фракций
          Expanded(
            child: _staffFractions.isEmpty
                ? Center(
              child: Text(
                'Нет доступных ${_typeFilter == 'all' ? 'кружков и клубов' : _typeFilter == 'circle' ? 'кружков' : 'клубов'}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            )
                : TabBarView(
              controller: _fractionTabController,
              children: _staffFractions.map((fraction) {
                return _buildFractionContent(fraction);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// Вспомогательный конвертер
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  final s = v.toString();
  return int.tryParse(s) ?? 0;
}

// Модели данных для сотрудника
class StaffFraction {
  final String id;
  final String title;
  final String type;
  final String category;
  final String coachName;
  final String? coachId;
  final String schedule;
  final String location;
  final int capacity;
  final int currentMembers;
  final bool isActive;
  final bool registrationOpen;
  final String? description;

  StaffFraction({
    required this.id,
    required this.title,
    required this.type,
    required this.category,
    required this.coachName,
    this.coachId,
    required this.schedule,
    required this.location,
    required this.capacity,
    required this.currentMembers,
    required this.isActive,
    required this.registrationOpen,
    this.description,
  });

  factory StaffFraction.fromJson(Map<String, dynamic> json) {
    return StaffFraction(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      coachName: json['coach_name']?.toString() ?? '',
      coachId: json['coach_id']?.toString(),
      schedule: json['schedule']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      capacity: _toInt(json['capacity']),
      currentMembers: _toInt(json['current_members']),
      isActive: json['is_active'] as bool? ?? true,
      registrationOpen: json['registration_open'] as bool? ?? true,
      description: json['description']?.toString(),
    );
  }
}

class FractionMember {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final String studentGroup;
  final String? avatarUrl;
  final String? phone;
  final DateTime joinedAt;

  FractionMember({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.studentGroup,
    this.avatarUrl,
    this.phone,
    required this.joinedAt,
  });

  factory FractionMember.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'] is Map
        ? Map<String, dynamic>.from(json['profiles'])
        : <String, dynamic>{};

    return FractionMember(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      fullName: profiles['full_name']?.toString() ?? 'Неизвестный студент',
      email: profiles['email']?.toString() ?? '',
      studentGroup: profiles['student_group']?.toString() ?? '',
      avatarUrl: profiles['avatar_url']?.toString(),
      phone: profiles['phone']?.toString(),
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'].toString())
          : DateTime.now(),
    );
  }
}

class FractionAttendanceRecord {
  final String id;
  final String sectionId;
  final String userId;
  final DateTime date;
  final AttendanceStatus status;
  final String notes;
  final String? recordedBy;
  final DateTime recordedAt;

  FractionAttendanceRecord({
    required this.id,
    required this.sectionId,
    required this.userId,
    required this.date,
    required this.status,
    required this.notes,
    this.recordedBy,
    required this.recordedAt,
  });

  factory FractionAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return FractionAttendanceRecord(
      id: json['id']?.toString() ?? '',
      sectionId: json['section_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      date: DateTime.parse(json['date'].toString()),
      status: AttendanceStatus.values.firstWhere(
            (e) => e.name == json['status']?.toString(),
        orElse: () => AttendanceStatus.absent,
      ),
      notes: json['notes']?.toString() ?? '',
      recordedBy: json['recorded_by']?.toString(),
      recordedAt: json['recorded_at'] != null
          ? DateTime.parse(json['recorded_at'].toString())
          : DateTime.now(),
    );
  }
}

class FractionApplication {
  final String id;
  final String applicantId;
  final String sectionId;
  final String status;
  final DateTime appliedAt;
  final DateTime? reviewedAt;
  final String motivation;
  final String studentName;
  final String studentEmail;
  final String studentGroup;
  final String? studentAvatar;
  final String sectionTitle;
  final String sectionType;
  final String sectionCategory;
  final String sectionSchedule;
  final String sectionLocation;

  FractionApplication({
    required this.id,
    required this.applicantId,
    required this.sectionId,
    required this.status,
    required this.appliedAt,
    this.reviewedAt,
    required this.motivation,
    required this.studentName,
    required this.studentEmail,
    required this.studentGroup,
    this.studentAvatar,
    required this.sectionTitle,
    required this.sectionType,
    required this.sectionCategory,
    required this.sectionSchedule,
    required this.sectionLocation,
  });

  factory FractionApplication.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'] is Map
        ? Map<String, dynamic>.from(json['profiles'])
        : <String, dynamic>{};
    final sections = json['extended_sections'] is Map
        ? Map<String, dynamic>.from(json['extended_sections'])
        : <String, dynamic>{};

    return FractionApplication(
      id: json['id']?.toString() ?? '',
      applicantId: json['applicant_id']?.toString() ?? '',
      sectionId: json['section_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      appliedAt: json['applied_at'] != null
          ? DateTime.parse(json['applied_at'].toString())
          : DateTime.now(),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'].toString())
          : null,
      motivation: json['motivation']?.toString() ?? '',
      studentName: profiles['full_name']?.toString() ?? 'Неизвестный студент',
      studentEmail: profiles['email']?.toString() ?? '',
      studentGroup: profiles['student_group']?.toString() ?? '',
      studentAvatar: profiles['avatar_url']?.toString(),
      sectionTitle: sections['title']?.toString() ?? 'Неизвестная секция',
      sectionType: sections['type']?.toString() ?? '',
      sectionCategory: sections['category']?.toString() ?? '',
      sectionSchedule: sections['schedule']?.toString() ?? '',
      sectionLocation: sections['location']?.toString() ?? '',
    );
  }

  String get shortId => id.length > 8 ? '${id.substring(0, 8)}...' : id;
}

// Enum для статусов посещаемости
enum AttendanceStatus { present, absent, excused }

extension AttendanceStatusExtension on AttendanceStatus {
  String get name {
    switch (this) {
      case AttendanceStatus.present:
        return 'present';
      case AttendanceStatus.absent:
        return 'absent';
      case AttendanceStatus.excused:
        return 'excused';
    }
  }

  String get displayName {
    switch (this) {
      case AttendanceStatus.present:
        return 'Присутствовал';
      case AttendanceStatus.absent:
        return 'Отсутствовал';
      case AttendanceStatus.excused:
        return 'По ув. причине';
    }
  }
}