import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as excel;
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../core/theme.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  // Службы
  final SupabaseClient _supabase = Supabase.instance.client;
  late TabController _tabController;

  List<Map<String, dynamic>> _sportSectionsForReport = [];
  List<Map<String, dynamic>> _clubSectionsForReport = [];
  String? _selectedSectionTypeReport; // 'sport' или 'club'
  String? _selectedSectionIdReport;
  DateTime? _selectedReportDate;
  List<Map<String, dynamic>> _sectionAttendanceReport = [];

  bool _checkingRole = true;
  Map<String, dynamic>? _currentUserProfile;

  // Состояние загрузки
  bool _studentsLoaded = false;
  bool _ticketsLoaded = false;
  Map<String, Map<String, dynamic>> _ticketsCache = {};
  List<Map<String, dynamic>> _studentsCache = [];
  DateTime _lastCacheUpdate = DateTime.now();
  final _cacheDuration = const Duration(minutes: 5); // Кэшируем на 5 минут
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isExporting = false;
  String? _errorMessage;

  // Данные
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _availableStudents = [];
  Map<String, dynamic> _canteenStats = {
    'total_students': 0,
    'average_attendance': 0,
    'student_details': [],
  };

  // Фильтры и поиск
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _ticketSearchController = TextEditingController();
  String _searchQuery = '';
  String _ticketSearchQuery = '';

  // Для отчетов по секциям
  List<Map<String, dynamic>> _sportSections = [];
  List<Map<String, dynamic>> _clubSections = [];
  String? _selectedSectionType; // 'sport' или 'club'
  String? _selectedSectionId;
  DateTime? _sectionReportStartDate;
  DateTime? _sectionReportEndDate;
  List<Map<String, dynamic>> _sectionAttendanceData = [];
  bool _isLoadingSectionReport = false;

  // Для активации талонов
  Map<String, dynamic>? _selectedStudent;
  String? _selectedPeriod;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  // Добавьте эти контроллеры рядом с другими
  final TextEditingController _iinController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();

  DateTimeRange? _selectedDateRange;
  final List<String> _exportTypes = [
    'Все студенты',
    'По группам',
    'QR коды',
    'Спортивные секции',
    'Фракции (кружки)'
  ];
  String? _selectedExportType;
  List<String> _availableGroups = [];
  String? _selectedGroup;

  // Новые данные для отчетов по секциям
  Map<String, dynamic> _sectionStats = {
    'sport_sections': [],
    'club_sections': [],
    'attendance_data': [],
    'selected_type': null,
    'selected_section': null,
  };



  // Новые переменные для отчетов по группам
  List<Map<String, dynamic>> _groupReportData = [];
  Map<String, dynamic> _selectedGroupStats = {};
  bool _isGroupReportLoading = false;

  // Для QR кодов отчетов
  final List<String> _qrPeriods = [
    'За неделю',
    'За месяц',
    'За год',
    'Все неиспользованные'
  ];
  String? _selectedQrPeriod;
  DateTime? _qrStartDate;
  DateTime? _qrEndDate;

  List<Map<String, dynamic>> _availableStudentsCache = [];
  bool _availableStudentsLoaded = false;
  bool _isLoadingTickets = false;

  // Контроллеры прокрутки для отчетов
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  // Для добавления/редактирования студентов
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _groupController = TextEditingController();
  final TextEditingController _specialityController = TextEditingController();
  Map<String, dynamic>? _editingStudent;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _tabController = TabController(length: 4, vsync: this); // Увеличиваем количество вкладок до 4

    _tabController.addListener(() {
      final currentIndex = _tabController.index;

      switch (currentIndex) {
        case 0: // Студенты
          if (!_studentsLoaded) {
            _loadAllStudents();
          }
          break;
        case 1: // Талон
          if (!_availableStudentsLoaded || _availableStudents.isEmpty) {
            _loadAvailableStudents();
          }
          break;
        case 2: // Отчеты (столовой)
          if (_canteenStats['student_details']?.isEmpty ?? true) {
            _loadCanteenStats();
          }
          break;
        case 3: // Отчеты секций (новый таб)
          if (_sportSectionsForReport.isEmpty && _clubSectionsForReport.isEmpty) {
            _loadSectionsForReport();
          }
          break;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadSectionsForReport() async {
    try {
      // Загружаем спортивные секции
      final sportSectionsResponse = await _supabase
          .from('extended_sections')
          .select('id, title, type, category, coach_name')
          .eq('type', 'sport')
          .eq('is_active', true)
          .order('title');

      // Загружаем кружки
      final clubSectionsResponse = await _supabase
          .from('extended_sections')
          .select('id, title, type, category, coach_name')
          .eq('type', 'club')
          .eq('is_active', true)
          .order('title');

      if (mounted) {
        setState(() {
          _sportSectionsForReport = List<Map<String, dynamic>>.from(sportSectionsResponse);
          _clubSectionsForReport = List<Map<String, dynamic>>.from(clubSectionsResponse);
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки секций для отчета: $e');
      _showSnackBar('Ошибка загрузки списка секций', isError: true);
    }
  }

  // Метод для загрузки отчета по посещаемости
  Future<void> _loadSectionAttendanceReport() async {
    if (_selectedReportDate == null) {
      _showSnackBar('Выберите дату для отчета', isError: true);
      return;
    }

    if (_selectedSectionTypeReport == null) {
      _showSnackBar('Выберите тип секции', isError: true);
      return;
    }

    try {
      setState(() => _isLoadingSectionReport = true);

      // Используем RPC функцию для получения отчета
      final reportData = await _supabase.rpc(
          'get_section_attendance_report',
          params: {
            'section_type_param': _selectedSectionTypeReport,
            'section_id_param': _selectedSectionIdReport,
            'report_date_param': _selectedReportDate!.toIso8601String().split('T')[0]
          }
      );

      if (mounted) {
        setState(() {
          _sectionAttendanceReport = List<Map<String, dynamic>>.from(reportData);
          _isLoadingSectionReport = false;
        });
      }

      if (_sectionAttendanceReport.isEmpty) {
        _showSnackBar('Нет данных о посещаемости за выбранную дату');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки отчета по посещаемости: $e');
      if (mounted) {
        setState(() => _isLoadingSectionReport = false);
      }
      _showSnackBar('Ошибка загрузки отчета: ${e.toString()}', isError: true);
    }
  }

  // Метод для экспорта отчета в Excel
  Future<void> _exportSectionAttendanceReport() async {
    if (_sectionAttendanceReport.isEmpty) {
      _showSnackBar('Нет данных для экспорта', isError: true);
      return;
    }

    try {
      setState(() => _isExporting = true);

      final String reportType = _selectedSectionTypeReport == 'sport'
          ? 'Спортивные_секции'
          : 'Кружки';

      String sectionTitle = 'Все_секции';
      if (_selectedSectionIdReport != null) {
        final allSections = [..._sportSectionsForReport, ..._clubSectionsForReport];
        final section = allSections.firstWhere(
                (s) => s['id'].toString() == _selectedSectionIdReport,
            orElse: () => {'title': 'Неизвестная_секция'}
        );
        sectionTitle = section['title']?.toString().replaceAll(RegExp(r'[^\w\s-]'), '_') ?? 'Неизвестная_секция';
      }

      final fileName = 'Отчет_${reportType}_${sectionTitle}_${DateFormat('yyyy-MM-dd').format(_selectedReportDate!)}.xlsx';

      final filePath = await _generateSectionAttendanceReport(
        _sectionAttendanceReport,
        fileName,
        _selectedReportDate!,
      );

      print('Отчет создан: $filePath');

      // Открываем файл
      try {
        final result = await OpenFile.open(filePath);

        if (result.type != ResultType.done) {
          await Share.shareXFiles(
            [XFile(filePath)],
            text: 'Отчет посещаемости $reportType',
            subject: 'Отчет по секциям',
          );
          _showSnackBar('Отчет готов к отправке');
        } else {
          _showSnackBar('Отчет открыт в приложении для просмотра');
        }
      } catch (e) {
        debugPrint('Ошибка при открытии файла: $e');
        _showSnackBar(
          'Отчет сохранен: ${filePath.split('/').last}',
          isError: false,
        );
      }
    } catch (e) {
      debugPrint('Ошибка экспорта отчета: $e');
      _showSnackBar('Ошибка экспорта: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // Метод генерации Excel файла
  Future<String> _generateSectionAttendanceReport(
      List<Map<String, dynamic>> reportData,
      String fileName,
      DateTime reportDate,
      ) async {
    try {
      final excel.Excel workbook = excel.Excel.createExcel();

      // Определяем имя листа в зависимости от типа
      String sheetName;
      if (_selectedSectionTypeReport == 'sport') {
        sheetName = 'Спортивные_секции';
      } else {
        sheetName = 'Кружки';
      }

      // Ограничиваем длину имени листа (Excel ограничивает 31 символ)
      if (sheetName.length > 31) {
        sheetName = sheetName.substring(0, 31);
      }

      final excel.Sheet sheet = workbook[sheetName];

      // Заголовок отчета
      sheet.appendRow(['Отчет по посещаемости']);
      sheet.appendRow([_selectedSectionTypeReport == 'sport' ? 'Спортивные секции' : 'Кружки']);
      sheet.appendRow(['Дата: ${DateFormat('dd.MM.yyyy').format(reportDate)}']);
      sheet.appendRow(['']);

      // Заголовки таблицы
      sheet.appendRow([
        '№',
        'ФИО студента',
        'Группа',
        'Специальность',
        'Секция/Кружок',
        'Дата',
        'Посещение',
        'Время отметки'
      ]);

      // Данные
      for (int i = 0; i < reportData.length; i++) {
        final record = reportData[i];

        // Преобразуем статус посещения
        String attendanceStatus;
        switch (record['attendance_status']) {
          case 'present':
            attendanceStatus = 'Присутствовал';
            break;
          case 'absent':
            attendanceStatus = 'Отсутствовал';
            break;
          case 'excused':
            attendanceStatus = 'По уважительной причине';
            break;
          default:
            attendanceStatus = record['attendance_status']?.toString() ?? 'Неизвестно';
        }

        // Форматируем дату и время
        String markedTime = '';
        if (record['marked_at'] != null) {
          try {
            final markedAt = DateTime.parse(record['marked_at'].toString());
            markedTime = DateFormat('HH:mm').format(markedAt);
          } catch (e) {
            debugPrint('Ошибка парсинга времени: $e');
          }
        }

        sheet.appendRow([
          i + 1,
          record['full_name'] ?? '',
          record['student_group'] ?? '',
          record['student_speciality'] ?? '',
          record['section_title'] ?? '',
          DateFormat('dd.MM.yyyy').format(DateTime.parse(record['attendance_date'].toString())),
          attendanceStatus,
          markedTime
        ]);
      }

      // Сводная информация
      sheet.appendRow(['']);
      sheet.appendRow(['Сводная информация:']);
      sheet.appendRow(['Всего записей:', reportData.length]);

      final presentCount = reportData.where((r) => r['attendance_status'] == 'present').length;
      final absentCount = reportData.where((r) => r['attendance_status'] == 'absent').length;
      final excusedCount = reportData.where((r) => r['attendance_status'] == 'excused').length;

      sheet.appendRow(['Присутствовали:', presentCount]);
      sheet.appendRow(['Отсутствовали:', absentCount]);
      sheet.appendRow(['По уважительной причине:', excusedCount]);

      final totalStudents = reportData.map((r) => r['student_id']).toSet().length;
      sheet.appendRow(['Уникальных студентов:', totalStudents]);

      // Сохраняем файл
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      final List<int>? bytes = workbook.save();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        print('Файл сохранен: $filePath, размер: ${bytes.length} байт');
      } else {
        throw Exception('Не удалось сохранить Excel файл');
      }

      return filePath;
    } catch (e) {
      debugPrint('Ошибка генерации отчета: $e');
      rethrow;
    }
  }

  // Метод для выбора даты
  Future<void> _selectReportDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedReportDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() => _selectedReportDate = picked);
    }
  }



  Future<void> _checkUserRole() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        _redirectToLogin();
        return;
      }

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single()
          .timeout(const Duration(seconds: 5));

      _currentUserProfile = Map<String, dynamic>.from(profile);
      final role = _currentUserProfile?['role'] as String? ?? 'student';

      if (role != 'admin') {
        _redirectToHome();
        return;
      }

      setState(() => _checkingRole = false);
    } catch (e) {
      debugPrint('Ошибка проверки роли: $e');
      _redirectToHome();
    }
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/login');
    });
  }

  void _redirectToHome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/home');
    });
  }

  Timer? _searchDebounce;
  Timer? _ticketSearchDebounce;

  void _debounceSearch() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  void _debounceTicketSearch() {
    if (_ticketSearchDebounce?.isActive ?? false) _ticketSearchDebounce!
        .cancel();
    _ticketSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() =>
      _ticketSearchQuery = _ticketSearchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _ticketSearchController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _groupController.dispose();
    _specialityController.dispose();
    _iinController.dispose();
    _categoryController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() => _isLoading = true);
      _errorMessage = null;

      // Загружаем только группы и минимальные данные
      await _loadGroups();

      // Предзагружаем студентов для текущей вкладки
      if (_tabController.index == 0) {
        await _loadAllStudents();
      }

      print('Основные данные загружены успешно');
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка загрузки данных: ${e.toString()}';
      });
      debugPrint('Ошибка загрузки данных: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAllStudents() async {
    try {
      // Проверяем кэш
      if (_studentsLoaded &&
          DateTime.now().difference(_lastCacheUpdate) < _cacheDuration &&
          _studentsCache.isNotEmpty) {
        print('Используем кэшированных студентов: ${_studentsCache.length}');
        if (mounted) {
          setState(() => _students = _studentsCache);
        }
        return;
      }

      print('Начинаем загрузку всех студентов...');

      List<Map<String, dynamic>> allStudents = [];
      int offset = 0;
      const int pageSize = 500; // Уменьшаем размер страницы

      // Используем запрос с минимальными полями
      while (true) {
        final response = await _supabase
            .from('profiles')
            .select('''
              id, 
              full_name, 
              email, 
              student_group, 
              student_speciality,
              iin,
              phone,
              date_of_birth,
              created_at
            ''')
            .eq('role', 'student')
            .order('full_name')
            .range(offset, offset + pageSize - 1)
            .limit(pageSize);

        if (response.isEmpty) break;

        allStudents.addAll(List<Map<String, dynamic>>.from(response));
        offset += pageSize;

        // Делаем небольшую паузу между запросами
        if (response.length == pageSize) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      print('Всего загружено студентов: ${allStudents.length}');

      // Сохраняем в кэш
      _studentsCache = allStudents;
      _studentsLoaded = true;
      _lastCacheUpdate = DateTime.now();

      if (mounted) {
        setState(() => _students = allStudents);
      }
    } catch (e) {
      debugPrint('Ошибка загрузки студентов: $e');
      // При ошибке используем кэш, если есть
      if (_studentsCache.isNotEmpty) {
        setState(() => _students = _studentsCache);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _loadAvailableStudents() async {
    try {
      // Проверяем кэш
      if (_availableStudentsLoaded &&
          DateTime.now().difference(_lastCacheUpdate) < _cacheDuration &&
          _availableStudentsCache.isNotEmpty) {
        print('Используем кэшированных доступных студентов: ${_availableStudentsCache.length}');
        if (mounted) {
          setState(() => _availableStudents = _availableStudentsCache);
        }
        return;
      }

      setState(() => _isLoadingTickets = true);

      print('Начинаем загрузку студентов с категорией "Free Payer"...');

      List<Map<String, dynamic>> allStudents = [];
      int offset = 0;
      const int pageSize = 500;

      // Загружаем только студентов с категорией "Free Payer"
      while (true) {
        final response = await _supabase
            .from('profiles')
            .select('id, full_name, student_group, student_speciality, category')
            .eq('role', 'student')
            .eq('category', 'Free Payer') // ← ФИЛЬТР ПО КАТЕГОРИИ
            .order('full_name')
            .range(offset, offset + pageSize - 1)
            .limit(pageSize);

        if (response.isEmpty) break;

        allStudents.addAll(List<Map<String, dynamic>>.from(response));
        offset += pageSize;

        if (response.length == pageSize) {
          await Future.delayed(const Duration(milliseconds: 30));
        }
      }

      print('Загружено студентов с категорией "Free Payer": ${allStudents.length}');

      if (allStudents.isEmpty) {
        print('Не найдено студентов с категорией "Free Payer"');
        if (mounted) {
          setState(() {
            _availableStudents = [];
            _availableStudentsCache = [];
            _availableStudentsLoaded = true;
            _isLoadingTickets = false;
          });
        }
        return;
      }

      // Получаем ID студентов для фильтрации
      final studentIds = allStudents.map((s) => s['id'].toString()).toList();

      // Используем inFilter с разбивкой на пакеты
      final Set<String> studentsWithActiveTickets = {};
      const int batchSize = 100; // Разбиваем на пакеты по 100 ID

      for (int i = 0; i < studentIds.length; i += batchSize) {
        final end = i + batchSize < studentIds.length ? i + batchSize : studentIds.length;
        final batchIds = studentIds.sublist(i, end);

        try {
          final batchTickets = await _supabase
              .from('tickets')
              .select('student_id')
              .eq('is_active', true)
              .inFilter('student_id', batchIds)
              .limit(batchSize * 2);

          for (var ticket in batchTickets) {
            final studentId = ticket['student_id']?.toString();
            if (studentId != null) {
              studentsWithActiveTickets.add(studentId);
            }
          }
        } catch (e) {
          debugPrint('Ошибка при запросе пакета ${i ~/ batchSize}: $e');
          // Продолжаем с следующим пакетом
        }

        // Небольшая пауза между запросами
        if (end < studentIds.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      // Формируем финальный список
      final List<Map<String, dynamic>> students = allStudents.map((student) {
        return {
          ...student,
          'has_active_ticket': studentsWithActiveTickets.contains(student['id'].toString()),
        };
      }).toList();

      // Сохраняем в кэш
      _availableStudentsCache = students;
      _availableStudentsLoaded = true;

      if (mounted) {
        setState(() {
          _availableStudents = students;
          _isLoadingTickets = false;
        });
      }

      print('Доступные студенты (Free Payer) загружены: ${students.length}');

    } catch (e) {
      debugPrint('Ошибка загрузки доступных студентов: $e');

      // При ошибке используем кэш, если есть
      if (_availableStudentsCache.isNotEmpty) {
        setState(() {
          _availableStudents = _availableStudentsCache;
          _isLoadingTickets = false;
        });
      } else {
        setState(() => _isLoadingTickets = false);
      }
    }
  }

  Future<void> _updateStudentCategory(String studentId, String category) async {
    try {
      await _supabase
          .from('profiles')
          .update({
        'category': category,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', studentId);

      print('Категория студента $studentId обновлена на: $category');

      // Сбрасываем кэш, чтобы обновить данные
      _availableStudentsLoaded = false;
      _availableStudentsCache.clear();

      // Перезагружаем список доступных студентов
      await _loadAvailableStudents();

    } catch (e) {
      debugPrint('Ошибка обновления категории студента: $e');
      rethrow;
    }
  }

  // === Исправленный _loadCanteenStats ===
  Future<void> _loadCanteenStats() async {
    try {
      final now = DateTime.now();
      final startDate = _selectedDateRange?.start ?? now.subtract(const Duration(days: 30));
      final endDate = _selectedDateRange?.end ?? now;

      print('Оптимизированная загрузка статистики...');

      // Пытаемся использовать RPC функцию
      try {
        final statsResponse = await _supabase.rpc('get_students_stats', params: {
          'start_date_param': startDate.toIso8601String().split('T')[0],
          'end_date_param': endDate.toIso8601String().split('T')[0]
        }).limit(3000);

        if (statsResponse != null && statsResponse.isNotEmpty) {
          // Вспомогательная функция для безопасного приведения к int
          int toIntSafe(dynamic v) {
            if (v == null) return 0;
            if (v is int) return v;
            if (v is double) return v.toInt();
            if (v is num) return v.toInt();
            if (v is String) {
              return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
            }
            return 0;
          }

          final List<Map<String, dynamic>> studentDetails = [];
          int totalUsedDays = 0;
          int totalDays = 0;
          int studentCount = 0;

          for (var student in statsResponse) {
            final int usedDays = toIntSafe(student['used_days']);
            final int totalStudentDays = toIntSafe(student['total_days']);
            final int attendanceRate = totalStudentDays > 0
                ? ((usedDays.toDouble() / totalStudentDays.toDouble()) * 100).round()
                : 0;

            studentDetails.add({
              'id': student['id'],
              'full_name': student['full_name'],
              'group': student['student_group'],
              'speciality': student['student_speciality'],
              'used_days': usedDays,
              'total_days': totalStudentDays,
              'attendance_rate': attendanceRate,
            });

            totalUsedDays += usedDays;
            totalDays += totalStudentDays;
            studentCount++;
          }

          final int averageAttendance = studentCount > 0 && totalDays > 0
              ? ((totalUsedDays.toDouble() / totalDays.toDouble()) * 100).round()
              : 0;

          if (mounted) {
            setState(() {
              _canteenStats = {
                'total_students': studentCount,
                'average_attendance': averageAttendance,
                'student_details': studentDetails,
                'period_start': DateFormat('dd.MM.yyyy').format(startDate),
                'period_end': DateFormat('dd.MM.yyyy').format(endDate),
              };
            });
          }

          print('Статистика загружена через RPC: $studentCount студентов');
          return;
        }
      } catch (e) {
        debugPrint('Ошибка RPC запроса, используем альтернативный метод: $e');
      }

      // Если RPC не сработал, используем альтернативный метод
      await _loadCanteenStatsAlternative(startDate, endDate);

    } catch (e) {
      debugPrint('Ошибка загрузки статистики: $e');
      await _loadCanteenStatsAlternative(
          _selectedDateRange?.start ?? DateTime.now().subtract(const Duration(days: 30)),
          _selectedDateRange?.end ?? DateTime.now()
      );
    }
  }

// Альтернативный метод для загрузки статистики
  // === Исправленный _loadCanteenStatsAlternative ===
  Future<void> _loadCanteenStatsAlternative(DateTime startDate,
      DateTime endDate) async {
    try {
      // Вспомогательная функция для безопасного приведения к int
      int toIntSafe(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is double) return v.toInt();
        if (v is num) return v.toInt();
        if (v is String) {
          return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
        }
        return 0;
      }

      // Загружаем студентов пакетами
      final students = _students.isNotEmpty
          ? _students
          : await _loadStudentsForStats();

      // Получаем статистику талонов за период
      final ticketsStats = await _supabase
          .from('tickets')
          .select('student_id, total_days, used_days')
          .lte('start_date', endDate.toIso8601String().split('T')[0])
          .gte('end_date', startDate.toIso8601String().split('T')[0])
          .limit(5000);

      // Создаем Map для быстрого поиска
      final Map<String, Map<String, int>> ticketsMap = {};
      for (var ticket in ticketsStats) {
        final studentId = ticket['student_id']?.toString();
        if (studentId != null) {
          ticketsMap.putIfAbsent(
              studentId, () => {'total_days': 0, 'used_days': 0});
          final int ticketTotal = toIntSafe(ticket['total_days']);
          final int ticketUsed = toIntSafe(ticket['used_days']);

          // безопасно суммируем (на случай, если значение было null)
          ticketsMap[studentId]!['total_days'] =
              (ticketsMap[studentId]!['total_days'] ?? 0) + ticketTotal;
          ticketsMap[studentId]!['used_days'] =
              (ticketsMap[studentId]!['used_days'] ?? 0) + ticketUsed;
        }
      }

      // Формируем данные студентов с ограничением для отображения
      final List<Map<String, dynamic>> studentDetails = [];
      const int maxDisplayStudents = 1000; // Ограничиваем отображение

      for (int i = 0; i < students.length && i < maxDisplayStudents; i++) {
        final student = students[i];
        final studentId = student['id'].toString();
        final stats = ticketsMap[studentId] ??
            {'total_days': 0, 'used_days': 0};

        final int totalDaysForStudent = toIntSafe(stats['total_days']);
        final int usedDaysForStudent = toIntSafe(stats['used_days']);

        final int attendanceRate = totalDaysForStudent > 0
            ? ((usedDaysForStudent.toDouble() /
            totalDaysForStudent.toDouble()) * 100).round()
            : 0;

        studentDetails.add({
          'id': student['id'],
          'full_name': student['full_name'],
          'group': student['student_group'],
          'speciality': student['student_speciality'],
          'used_days': usedDaysForStudent,
          'total_days': totalDaysForStudent,
          'attendance_rate': attendanceRate,
        });
      }

      if (mounted) {
        setState(() {
          _canteenStats = {
            'total_students': students.length,
            'average_attendance': 0, // Рассчитываем по требованию
            'student_details': studentDetails,
            'period_start': DateFormat('dd.MM.yyyy').format(startDate),
            'period_end': DateFormat('dd.MM.yyyy').format(endDate),
            'has_more_students': students.length > maxDisplayStudents,
            'total_students_count': students.length,
          };
        });
      }
    } catch (e) {
      debugPrint('Ошибка альтернативной загрузки статистики: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadStudentsForStats() async {
    final response = await _supabase
        .from('profiles')
        .select('id, full_name, student_group, student_speciality')
        .eq('role', 'student')
        .order('full_name')
        .limit(3000);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> _getTicketsStatistics() async {
    try {
      print('Начинаем загрузку талонов...');

      List<Map<String, dynamic>> allTickets = [];
      int from = 0;
      const int pageSize = 1000;
      bool hasMore = true;
      int totalLoaded = 0;

      while (hasMore) {
        print('Загрузка талонов с $from по ${from + pageSize - 1}');

        final response = await _supabase
            .from('tickets')
            .select(
            'student_id, total_days, used_days, is_active, start_date, end_date')
            .order('created_at', ascending: false)
            .range(from, from + pageSize - 1);

        if (response.isNotEmpty) {
          final tickets = List<Map<String, dynamic>>.from(response);
          allTickets.addAll(tickets);
          totalLoaded += tickets.length;
          print('Загружено талонов: ${tickets.length} (всего: $totalLoaded)');

          if (tickets.length < pageSize) {
            hasMore = false;
            print('Завершена загрузка талонов, всего: $totalLoaded');
          } else {
            from += pageSize;
          }
        } else {
          hasMore = false;
          print('Больше нет талонов для загрузки');
        }
      }

      print('Всего загружено талонов: ${allTickets.length}');

      // Группируем по студентам
      final Map<String, Map<String, dynamic>> stats = {};

      for (var ticket in allTickets) {
        final studentId = ticket['student_id']?.toString();
        if (studentId != null) {
          if (!stats.containsKey(studentId)) {
            stats[studentId] = {
              'total_days': 0,
              'used_days': 0,
              'active_tickets': 0,
              'total_tickets': 0,
              'start_dates': [],
              'end_dates': [],
            };
          }

          stats[studentId]!['total_days'] += (ticket['total_days'] ?? 0) as int;
          stats[studentId]!['used_days'] += (ticket['used_days'] ?? 0) as int;
          stats[studentId]!['total_tickets'] =
              (stats[studentId]!['total_tickets'] as int) + 1;

          if (ticket['is_active'] == true) {
            stats[studentId]!['active_tickets'] =
                (stats[studentId]!['active_tickets'] as int) + 1;
          }

          if (ticket['start_date'] != null) {
            (stats[studentId]!['start_dates'] as List).add(
                ticket['start_date']);
          }
          if (ticket['end_date'] != null) {
            (stats[studentId]!['end_dates'] as List).add(ticket['end_date']);
          }
        }
      }

      return {
        'tickets': allTickets,
        'stats': stats,
        'total_tickets': allTickets.length,
        'active_tickets': allTickets
            .where((t) => t['is_active'] == true)
            .length,
      };
    } catch (e) {
      debugPrint('Ошибка загрузки статистики талонов: $e');
      return {
        'tickets': [],
        'stats': {},
        'total_tickets': 0,
        'active_tickets': 0,
      };
    }
  }

  Future<void> _testQueries() async {
    try {
      print('=== ТЕСТИРОВАНИЕ ЗАПРОСОВ ===');

      // Тест 1: Простой запрос студентов
      print('Тест 1: Запрос студентов...');
      final students = await _supabase
          .from('profiles')
          .select('count')
          .eq('role', 'student');
      print('Студентов в базе: $students');

      // Тест 2: Запрос талонов
      print('Тест 2: Запрос талонов...');
      final tickets = await _supabase
          .from('tickets')
          .select('count');
      print('Талонов в базе: $tickets');

      // Тест 3: Запрос использования талонов
      print('Тест 3: Запрос использования талонов...');
      try {
        final usage = await _supabase
            .from('ticket_usage')
            .select('count')
            .limit(1);
        print('Записей использования: $usage');
      } catch (e) {
        print('Таблица ticket_usage недоступна: $e');
      }

      print('=== ТЕСТ ЗАВЕРШЕН ===');
    } catch (e) {
      print('Ошибка тестирования: $e');
    }
  }

  Future<void> _loadGroups() async {
    try {
      print('Начинаем загрузку групп со специальностями...');

      List<Map<String, dynamic>> allGroupsData = [];
      int from = 0;
      const int pageSize = 1000;
      bool hasMore = true;
      int totalLoaded = 0;

      while (hasMore) {
        print('Загрузка групп с $from по ${from + pageSize - 1}');

        final response = await _supabase
            .from('profiles')
            .select('student_group, student_speciality')
            .eq('role', 'student')
            .not('student_group', 'is', null)
            .not('student_speciality', 'is', null)
            .order('student_group')
            .range(from, from + pageSize - 1);

        if (response.isNotEmpty) {
          final groups = List<Map<String, dynamic>>.from(response);
          allGroupsData.addAll(groups);
          totalLoaded += groups.length;
          print('Загружено записей групп: ${groups
              .length} (всего: $totalLoaded)');

          if (groups.length < pageSize) {
            hasMore = false;
            print('Завершена загрузка групп, всего записей: $totalLoaded');
          } else {
            from += pageSize;
          }
        } else {
          hasMore = false;
          print('Больше нет групп для загрузки');
        }
      }

      // Создаем уникальные комбинации группа-специальность
      final Set<String> uniqueGroupSpecialties = {};
      final List<String> formattedGroups = [];

      for (var data in allGroupsData) {
        final group = data['student_group']?.toString() ?? '';
        final speciality = data['student_speciality']?.toString() ?? '';

        if (group.isNotEmpty && speciality.isNotEmpty) {
          final formatted = '$group ($speciality)';
          if (!uniqueGroupSpecialties.contains(formatted)) {
            uniqueGroupSpecialties.add(formatted);
            formattedGroups.add(formatted);
          }
        }
      }

      // Сортируем по алфавиту
      formattedGroups.sort();

      if (mounted) {
        setState(() => _availableGroups = formattedGroups);
        print('Загружено уникальных групп со специальностями: ${formattedGroups
            .length}');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки групп со специальностями: $e');
    }
  }

  // === Исправленный _loadGroupReport ===
  Future<void> _loadGroupReport(String formattedGroup) async {
    try {
      setState(() => _isGroupReportLoading = true);

      final groupMatch = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(
          formattedGroup);
      if (groupMatch == null) {
        throw Exception('Неверный формат группы: $formattedGroup');
      }

      final groupName = groupMatch.group(1)?.trim() ?? '';
      final speciality = groupMatch.group(2)?.trim() ?? '';

      print('Оптимизированная загрузка отчета по группе: $groupName');

      // Вспомогательная функция для безопасного приведения к int
      int toIntSafe(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is double) return v.toInt();
        if (v is num) return v.toInt();
        if (v is String) {
          return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
        }
        return 0;
      }

      // Используем агрегатный запрос через RPC
      try {
        final reportData = await _supabase.rpc('get_group_report', params: {
          'group_name': groupName,
          'speciality_name': speciality
        }).limit(1000);

        if (reportData != null && reportData.isNotEmpty) {
          final List<Map<String, dynamic>> parsedData = List<
              Map<String, dynamic>>.from(reportData);

          // Рассчитываем общую статистику
          int totalTickets = 0;
          int totalUsedDays = 0;
          int totalUnusedDays = 0;

          for (var student in parsedData) {
            final int studentTotalTickets = toIntSafe(student['total_tickets']);
            final int studentUsedDays = toIntSafe(student['used_days']);
            final int studentUnusedDays = toIntSafe(student['unused_days']);

            totalTickets += studentTotalTickets;
            totalUsedDays += studentUsedDays;
            // защита от отрицательных значений
            totalUnusedDays += studentUnusedDays > 0 ? studentUnusedDays : 0;
          }

          setState(() {
            _groupReportData = parsedData;
            _selectedGroupStats = {
              'group': groupName,
              'speciality': speciality,
              'total_tickets': totalTickets,
              'total_used_days': totalUsedDays,
              'total_unused_days': totalUnusedDays,
              'student_count': parsedData.length,
            };
            _isGroupReportLoading = false;
          });

          return;
        }
      } catch (e) {
        debugPrint(
            'RPC запрос не сработал, используем альтернативный метод: $e');
      }

      // Альтернативный метод если RPC не доступен
      await _loadGroupReportAlternative(groupName, speciality);
    } catch (e) {
      debugPrint('Ошибка загрузки отчета по группе: $e');
      _showSnackBar('Ошибка загрузки отчета: ${e.toString()}', isError: true);
      setState(() => _isGroupReportLoading = false);
    }
  }


  // === Исправленный _loadGroupReportAlternative ===
  Future<void> _loadGroupReportAlternative(String groupName,
      String speciality) async {
    // Вспомогательная функция для безопасного приведения к int
    int toIntSafe(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is num) return v.toInt();
      if (v is String) {
        return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
      }
      return 0;
    }

    try {
      // Загружаем студентов группы
      final studentsResponse = await _supabase
          .from('profiles')
          .select('id, full_name, iin, phone, date_of_birth')
          .eq('role', 'student')
          .eq('student_group', groupName)
          .eq('student_speciality', speciality)
          .order('full_name')
          .limit(500);

      if (studentsResponse == null ||
          (studentsResponse is List && studentsResponse.isEmpty)) {
        throw Exception('Студентов не найдено для указанной группы');
      }

      final studentIds = (studentsResponse as List).map((s) =>
          s['id'].toString()).toList();

      // Загружаем статистику талонов для всех студентов одним запросом
      final ticketsResponse = await _supabase
          .from('tickets')
          .select('student_id, total_days, used_days')
          .inFilter('student_id', studentIds)
          .limit(1000);

      // Создаем Map для быстрого поиска статистики
      final Map<String, Map<String, int>> ticketsMap = {};
      if (ticketsResponse is List) {
        for (var ticket in ticketsResponse) {
          final studentId = ticket['student_id']?.toString();
          if (studentId != null) {
            ticketsMap.putIfAbsent(studentId, () =>
            {
              'total_days': 0,
              'used_days': 0,
              'total_tickets': 0,
            });

            final int ticketTotalDays = toIntSafe(ticket['total_days']);
            final int ticketUsedDays = toIntSafe(ticket['used_days']);

            ticketsMap[studentId]!['total_days'] =
                (ticketsMap[studentId]!['total_days'] ?? 0) + ticketTotalDays;
            ticketsMap[studentId]!['used_days'] =
                (ticketsMap[studentId]!['used_days'] ?? 0) + ticketUsedDays;
            ticketsMap[studentId]!['total_tickets'] =
                (ticketsMap[studentId]!['total_tickets'] ?? 0) + 1;
          }
        }
      }

      // Формируем данные отчета
      final List<Map<String, dynamic>> reportData = [];
      int totalTickets = 0;
      int totalUsedDays = 0;
      int totalUnusedDays = 0;

      for (var student in studentsResponse) {
        final studentId = student['id'].toString();
        final stats = ticketsMap[studentId] ?? {
          'total_days': 0,
          'used_days': 0,
          'total_tickets': 0,
        };

        final int studentTotalTickets = toIntSafe(stats['total_tickets']);
        final int studentUsedDays = toIntSafe(stats['used_days']);
        final int studentTotalDays = toIntSafe(stats['total_days']);

        final int studentUnusedDays = (studentTotalDays - studentUsedDays);
        final int normalizedUnusedDays = studentUnusedDays > 0
            ? studentUnusedDays
            : 0;

        totalTickets += studentTotalTickets;
        totalUsedDays += studentUsedDays;
        totalUnusedDays += normalizedUnusedDays;

        reportData.add({
          'student_name': student['full_name'],
          'student_id': studentId,
          'iin': student['iin'],
          'phone': student['phone'],
          'birth_date': student['date_of_birth'],
          'speciality': speciality,
          'group': groupName,
          'total_tickets': studentTotalTickets,
          'used_days': studentUsedDays,
          'unused_days': normalizedUnusedDays,
          'total_days': studentTotalDays,
        });
      }

      setState(() {
        _groupReportData = reportData;
        _selectedGroupStats = {
          'group': groupName,
          'speciality': speciality,
          'total_tickets': totalTickets,
          'total_used_days': totalUsedDays,
          'total_unused_days': totalUnusedDays,
          'student_count': (studentsResponse as List).length,
        };
        _isGroupReportLoading = false;
      });
    } catch (e) {
      debugPrint('Ошибка альтернативной загрузки отчета по группе: $e');
      _showSnackBar(
          'Ошибка формирования отчета: ${e.toString()}', isError: true);
      setState(() => _isGroupReportLoading = false);
    }
  }

  Future<void> _activateTicket() async {
    if (_selectedStudent == null) {
      _showSnackBar('Выберите студента', isError: true);
      return;
    }

    // Проверяем, что у студента категория "Free Payer"
    final studentCategory = _selectedStudent!['category']?.toString() ?? '';
    if (studentCategory != 'Free Payer') {
      _showSnackBar(
        'Только студенты с категорией "Free Payer" могут получить талон, перейдите в вкладку "Талоны". '
            'Текущая категория: $studentCategory',
        isError: true,
      );
      return;
    }

    try {
      // Показываем индикатор загрузки
      _showSnackBar('Активация талона...');

      final DateTime startDate;
      final DateTime endDate;

      // Определяем период
      if (_selectedPeriod != 'custom' && _selectedPeriod != null) {
        final now = DateTime.now();
        startDate = now;

        switch (_selectedPeriod) {
          case 'day':
            endDate = now;
            break;
          case 'week':
            endDate = now.add(const Duration(days: 6));
            break;
          case 'month':
            endDate = now.add(const Duration(days: 30));
            break;
          default:
            endDate = now;
        }
      } else if (_selectedStartDate != null && _selectedEndDate != null) {
        startDate = _selectedStartDate!;
        endDate = _selectedEndDate!;
      } else {
        _showSnackBar('Укажите период действия талона', isError: true);
        return;
      }

      // Проверяем даты
      if (endDate.isBefore(startDate)) {
        _showSnackBar(
            'Дата окончания не может быть раньше даты начала', isError: true);
        return;
      }

      final totalDays = endDate
          .difference(startDate)
          .inDays + 1;

      // Проверяем активные талоны с ограниченным запросом
      final existingTickets = await _supabase
          .from('tickets')
          .select('id')
          .eq('student_id', _selectedStudent!['id'])
          .eq('is_active', true)
          .lte('start_date', endDate
          .toIso8601String()
          .split('T')
          .first)
          .gte('end_date', startDate
          .toIso8601String()
          .split('T')
          .first)
          .limit(1);

      if (existingTickets.isNotEmpty) {
        _showSnackBar(
            'У студента уже есть активный талон на этот период', isError: true);
        return;
      }

      // Создаем талон
      final result = await _supabase.from('tickets').insert({
        'student_id': _selectedStudent!['id'],
        'start_date': startDate
            .toIso8601String()
            .split('T')
            .first,
        'end_date': endDate
            .toIso8601String()
            .split('T')
            .first,
        'is_active': true,
        'period_type': _selectedPeriod ?? 'custom',
        'total_days': totalDays,
        'used_days': 0,
        'missed_days': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'created_by': _supabase.auth.currentUser?.id,
      }).select();

      if (result.isNotEmpty) {
        final ticketId = result[0]['id'] as String;

        // Генерируем QR коды в фоновом режиме
        _generateDailyQRCodes(ticketId, startDate, endDate).then((_) {
          _showSnackBar(
              'Талон успешно активирован! Сгенерировано $totalDays QR-кодов');
        }).catchError((e) {
          debugPrint('Ошибка генерации QR кодов: $e');
          _showSnackBar(
              'Талон активирован, но возникла ошибка при генерации QR кодов',
              isError: true);
        });

        // Сбрасываем состояние
        setState(() {
          _selectedStudent = null;
          _selectedPeriod = null;
          _selectedStartDate = null;
          _selectedEndDate = null;
          _startDateController.clear();
          _endDateController.clear();
          _ticketSearchController.clear();
        });

        // Сбрасываем кэш для обновления статуса студента
        _availableStudentsLoaded = false;
        _availableStudentsCache.clear();

        // Показываем уведомление об успехе
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Талон успешно активирован!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Ошибка активации талона: $e');
      _showSnackBar('Ошибка активации: ${e.toString()}', isError: true);
    }
  }

  Future<void> _generateDailyQRCodes(String ticketId, DateTime startDate, DateTime endDate) async {
    try {
      final List<Map<String, dynamic>> qrCodes = [];

      debugPrint('Генерация QR с $startDate по $endDate');

      DateTime currentDate = startDate;

      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        final token = _generateSecureToken();

        // Используем локальное время для Алматы (UTC+6)
        final almatyDate = currentDate.toLocal();
        final expiresAt = DateTime(
          almatyDate.year,
          almatyDate.month,
          almatyDate.day,
          23, // 23:59:59 Алматы
          59,
          59,
        );

        qrCodes.add({
          'ticket_id': ticketId,
          'date': DateFormat('yyyy-MM-dd').format(almatyDate), // Дата в Алматы
          'token': token,
          'generated_at': DateTime.now().toIso8601String(),
          'expires_at': expiresAt.toIso8601String(), // Конец дня в Алматы
          'used': false,
          'scanned_by': null,
          'device_info': null,
          'ip_address': null,
          'used_at': null,
        });

        currentDate = currentDate.add(const Duration(days: 1));
      }

      // Вставляем пачками
      for (int i = 0; i < qrCodes.length; i += 100) {
        final end = i + 100 > qrCodes.length ? qrCodes.length : i + 100;
        final batch = qrCodes.sublist(i, end);

        final onConflictCols = ['ticket_id', 'date'].join(',');
        await _supabase
            .from('daily_qr_codes')
            .upsert(batch, onConflict: onConflictCols);
      }

      debugPrint('Сгенерировано ${qrCodes.length} QR-кодов для талона $ticketId');
    } catch (e) {
      debugPrint('Ошибка генерации QR-кодов: $e');
      rethrow;
    }
  }

  String _generateSecureToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url
        .encode(values)
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .substring(0, 32);
  }

  Future<bool> _requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 33) {
          return true;
        } else if (sdkInt >= 30) {
          return true;
        } else {
          final status = await Permission.storage.request();
          return status.isGranted;
        }
      } else if (Platform.isIOS) {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
      return true;
    } catch (e) {
      debugPrint('Ошибка при запросе разрешений: $e');
      return false;
    }
  }

  Future<void> _exportReport() async {
    try {
      setState(() => _isExporting = true);
      print(
          'Начало экспорта отчета. Тип: $_selectedExportType, Группа: $_selectedGroup');

      if (_selectedExportType == null) {
        _showSnackBar('Выберите тип отчета', isError: true);
        return;
      }

      if (_selectedExportType == 'По группам' && _selectedGroup == null) {
        _showSnackBar('Выберите группу для отчета', isError: true);
        return;
      }

      if (_selectedExportType == 'QR коды' && _selectedQrPeriod == null) {
        _showSnackBar('Выберите период для QR кодов', isError: true);
        return;
      }

      // Проверяем разрешения для Android
      if (Platform.isAndroid) {
        final hasPermission = await _checkAndRequestPermissions();
        if (!hasPermission) {
          _showSnackBar(
            'Для сохранения отчета необходимо предоставить разрешение на доступ к файлам',
            isError: true,
          );
          return;
        }
      }

      String fileName;
      String filePath;

      // Показываем индикатор загрузки
      _showSnackBar('Начинается генерация отчета...');

      switch (_selectedExportType) {
        case 'Все студенты':
          print('Генерация отчета "Все студенты"');
          fileName = 'Все_студенты_${DateFormat('yyyy-MM-dd_HH-mm').format(
              DateTime.now())}.xlsx';
          filePath = await _generateAllStudentsReport(fileName);
          break;
        case 'По группам':
          if (_selectedGroup == null) {
            _showSnackBar('Выберите группу для отчета', isError: true);
            return;
          }
          print('Генерация отчета по группе: $_selectedGroup');

          // Формируем имя файла без специальных символов
          final safeGroupName = _selectedGroup!.replaceAll(
              RegExp(r'[^\w\s-]'), '_');
          fileName =
          'Отчет_по_группе_${safeGroupName}_${DateFormat('yyyy-MM-dd_HH-mm')
              .format(DateTime.now())}.xlsx';

          filePath =
          await _generateGroupDetailReport(_selectedGroup!, fileName);
          break;
        case 'QR коды':
          print('Генерация отчета QR кодов: $_selectedQrPeriod');
          fileName =
          'QR_коды_${_selectedQrPeriod}_${DateFormat('yyyy-MM-dd_HH-mm').format(
              DateTime.now())}.xlsx';
          filePath = await _generateQRCodesReport(fileName);
          break;
        default:
          _showSnackBar('Неизвестный тип отчета', isError: true);
          return;
      }

      print('Отчет создан: $filePath');

      // Проверяем, существует ли файл
      final file = File(filePath);
      if (!await file.exists()) {
        _showSnackBar('Ошибка: файл не был создан', isError: true);
        return;
      }

      // Пытаемся открыть файл
      try {
        final result = await OpenFile.open(filePath);

        if (result.type != ResultType.done) {
          print('Не удалось открыть файл напрямую, тип ошибки: ${result.type}');

          // Пробуем поделиться файлом
          await Share.shareXFiles(
            [XFile(filePath)],
            text: 'Отчет $fileName',
            subject: 'Отчет по студентам',
          );

          _showSnackBar('Отчет готов к отправке');
        } else {
          _showSnackBar('Отчет открыт в приложении для просмотра');
        }
      } catch (e) {
        debugPrint('Ошибка при открытии файла: $e');

        // Если не удалось открыть, показываем информацию о файле
        _showSnackBar(
          'Отчет сохранен по пути: ${file.path}\nРазмер файла: ${(await file
              .length() / 1024).toStringAsFixed(2)} KB',
          isError: false,
        );
      }
    } catch (e) {
      debugPrint('Ошибка экспорта: $e');
      _showSnackBar('Ошибка экспорта: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    try {
      if (Platform.isAndroid) {
        final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 33) {
          // Android 13+ - запрашиваем разрешение на медиа
          final status = await Permission.photos.request();
          return status.isGranted;
        } else if (sdkInt >= 30) {
          // Android 11-12 - используем Scoped Storage
          return true;
        } else {
          // Android 10 и ниже - разрешение на хранилище
          final status = await Permission.storage.request();
          return status.isGranted;
        }
      } else if (Platform.isIOS) {
        // iOS - разрешение на доступ к файлам
        final status = await Permission.storage.request();
        return status.isGranted;
      }
      return true;
    } catch (e) {
      debugPrint('Ошибка при проверке разрешений: $e');
      return true; // Разрешаем продолжать, даже если ошибка
    }
  }

  Future<String> _generateAllStudentsReport(String fileName) async {
    try {
      final excel.Excel workbook = excel.Excel.createExcel();
      final excel.Sheet sheet = workbook['Студенты'];

      // Заголовки
      sheet.appendRow([
        'ID',
        'ФИО',
        'Email',
        'Группа',
        'Специальность',
        'Дата регистрации'
      ]);

      // Данные
      for (var student in _students) {
        sheet.appendRow([
          student['id'],
          student['full_name'] ?? '',
          student['email'] ?? '',
          student['student_group'] ?? 'Без группы',
          student['student_speciality'] ?? 'Не указана',
          DateFormat('dd.MM.yyyy').format(
              DateTime.parse(student['created_at'])),
        ]);
      }

      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      final List<int>? bytes = workbook.save();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      }

      return filePath;
    } catch (e) {
      debugPrint('Ошибка генерации отчета студентов: $e');
      rethrow;
    }
  }

  Future<String> _generateGroupDetailReport(String formattedGroup,
      String fileName) async {
    try {
      print('Начало генерации отчета для группы: $formattedGroup');

      // Разбираем строку формата "Группа (Специальность)"
      final groupMatch = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(
          formattedGroup);
      if (groupMatch == null) {
        print('Неверный формат группы: $formattedGroup');
        throw Exception('Неверный формат группы: $formattedGroup');
      }

      final groupName = groupMatch.group(1)?.trim() ?? '';
      final speciality = groupMatch.group(2)?.trim() ?? '';

      print('Разобрана группа: "$groupName", специальность: "$speciality"');

      // Загружаем студентов группы с пагинацией
      print('Загрузка студентов группы...');
      List<Map<String, dynamic>> studentsResponse = [];
      int from = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final response = await _supabase
            .from('profiles')
            .select(
            'id, full_name, student_speciality, student_group, iin, phone, date_of_birth')
            .eq('role', 'student')
            .eq('student_group', groupName)
            .eq('student_speciality', speciality)
            .order('full_name')
            .range(from, from + pageSize - 1);

        if (response.isNotEmpty) {
          studentsResponse.addAll(List<Map<String, dynamic>>.from(response));

          if (response.length < pageSize) {
            hasMore = false;
          } else {
            from += pageSize;
          }
        } else {
          hasMore = false;
        }
      }

      if (studentsResponse.isEmpty) {
        print('Студентов не найдено для группы: $groupName ($speciality)');
        throw Exception('Студентов не найдено для указанной группы');
      }

      print('Найдено студентов: ${studentsResponse.length}');

      // Получаем ID студентов
      final studentIds = studentsResponse
          .map((s) => s['id'].toString())
          .toList();

      // Загружаем талоны для этих студентов с пагинацией
      print('Загрузка талонов для студентов...');
      Map<String, Map<String, dynamic>> ticketStats = {};
      from = 0;
      hasMore = true;

      while (hasMore) {
        final ticketsResponse = await _supabase
            .from('tickets')
            .select('student_id, total_days, used_days')
            .inFilter('student_id', studentIds)
            .range(from, from + pageSize - 1);

        if (ticketsResponse.isNotEmpty) {
          for (var ticket in ticketsResponse) {
            final studentId = ticket['student_id'].toString();
            if (!ticketStats.containsKey(studentId)) {
              ticketStats[studentId] = {
                'total_days': 0,
                'used_days': 0,
                'total_tickets': 0,
              };
            }

            ticketStats[studentId]!['total_days'] +=
            (ticket['total_days'] ?? 0) as int;
            ticketStats[studentId]!['used_days'] +=
            (ticket['used_days'] ?? 0) as int;
            ticketStats[studentId]!['total_tickets'] += 1;
          }

          if (ticketsResponse.length < pageSize) {
            hasMore = false;
          } else {
            from += pageSize;
          }
        } else {
          hasMore = false;
        }
      }

      print('Найдено талонов для ${ticketStats.length} студентов');

      // Создаем Excel
      final excel.Excel workbook = excel.Excel.createExcel();
      final sheetName = groupName.length > 27 ? '${groupName.substring(
          0, 27)}...' : groupName;
      final excel.Sheet sheet = workbook[sheetName];

      // Заголовок отчета
      sheet.appendRow(['Отчет по группе: $groupName']);
      sheet.appendRow(['Специальность: $speciality']);
      sheet.appendRow(['Всего студентов: ${studentsResponse.length}']);
      sheet.appendRow([
        'Дата формирования: ${DateFormat('dd.MM.yyyy HH:mm').format(
            DateTime.now())}'
      ]);
      sheet.appendRow(['']);

      // Заголовки таблицы
      sheet.appendRow([
        '№',
        'ФИО студента',
        'ИИН',
        'Телефон',
        'Дата рождения',
        'Всего талонов',
        'Использованных дней',
        'Неиспользованных дней',
        'Всего дней',
        'Процент использования',
      ]);

      num totalTickets = 0;
      num totalUsedDays = 0;
      num totalUnusedDays = 0;
      num totalDays = 0;

      // Данные студентов
      for (int i = 0; i < studentsResponse.length; i++) {
        final student = studentsResponse[i];
        final studentId = student['id'].toString();
        final stats = ticketStats[studentId] ?? {
          'total_days': 0,
          'used_days': 0,
          'total_tickets': 0,
        };

        final studentTotalTickets = stats['total_tickets'] ?? 0;
        final studentUsedDays = stats['used_days'] ?? 0;
        final studentTotalDays = stats['total_days'] ?? 0;
        final studentUnusedDays = studentTotalDays - studentUsedDays;
        final usagePercent = studentTotalDays > 0 ? (studentUsedDays /
            studentTotalDays * 100).round() : 0;

        totalTickets += studentTotalTickets;
        totalUsedDays += studentUsedDays;
        totalUnusedDays += studentUnusedDays > 0 ? studentUnusedDays : 0;
        totalDays += studentTotalDays;

        sheet.appendRow([
          i + 1,
          student['full_name'] ?? '',
          student['iin'] ?? '',
          student['phone'] ?? '',
          student['date_of_birth'] ?? '',
          studentTotalTickets,
          studentUsedDays,
          studentUnusedDays,
          studentTotalDays,
          '$usagePercent%',
        ]);
      }

      // Сводная информация
      sheet.appendRow(['']);
      sheet.appendRow(['Сводная информация по группе:']);
      sheet.appendRow(['Группа:', groupName]);
      sheet.appendRow(['Специальность:', speciality]);
      sheet.appendRow(['Всего студентов:', studentsResponse.length]);
      sheet.appendRow(['Всего талонов:', totalTickets]);
      sheet.appendRow(['Общее количество дней:', totalDays]);
      sheet.appendRow(['Использовано дней:', totalUsedDays]);
      sheet.appendRow(['Не использовано дней:', totalUnusedDays]);

      final totalUsagePercent = totalDays > 0 ? (totalUsedDays / totalDays *
          100).round() : 0;
      sheet.appendRow(['Общий процент использования:', '$totalUsagePercent%']);

      // Сохраняем файл
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      final List<int>? bytes = workbook.save();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        print('Файл сохранен: $filePath');
        print('Размер файла: ${bytes.length} байт');
      } else {
        throw Exception('Не удалось сохранить Excel файл');
      }

      return filePath;
    } catch (e) {
      debugPrint('Ошибка генерации отчета по группе: $e');
      rethrow;
    }
  }

  Future<String> _generateQRCodesReport(String fileName) async {
    try {
      DateTime startDate;
      final endDate = DateTime.now();

      switch (_selectedQrPeriod) {
        case 'За неделю':
          startDate = endDate.subtract(const Duration(days: 7));
          break;
        case 'За месяц':
          startDate = endDate.subtract(const Duration(days: 30));
          break;
        case 'За год':
          startDate = endDate.subtract(const Duration(days: 365));
          break;
        case 'Все неиспользованные':
          startDate = DateTime(2023, 1, 1);
          break;
        default:
          startDate = endDate.subtract(const Duration(days: 30));
      }

      final qrCodes = await _loadQRCodes(startDate, endDate);

      if (qrCodes.isEmpty) {
        throw Exception('Нет QR кодов для выбранного периода');
      }

      final excel.Excel workbook = excel.Excel.createExcel();
      final excel.Sheet sheet = workbook['QR коды'];

      sheet.appendRow([
        'Группа',
        'Студент',
        'QR код',
        'Дата действия',
        'Истекает',
        'Токен (текст)'
      ]);

      for (int i = 0; i < qrCodes.length; i++) {
        final qr = qrCodes[i];
        final token = qr['token'] ?? '';
        final studentName = qr['student'] ?? '';
        final group = qr['group'] ?? '';
        final date = qr['date'] ?? '';
        final expires = qr['expires'] ?? '';

        sheet.appendRow([
          group,
          studentName,
          'QR код для даты: $date',
          date,
          expires,
          token,
        ]);
      }

      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      final List<int>? bytes = workbook.save();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      }

      return filePath;
    } catch (e) {
      debugPrint('Ошибка генерации отчета QR кодов: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _loadQRCodes(DateTime startDate,
      DateTime endDate) async {
    try {
      print('Загрузка QR кодов с $startDate по $endDate');

      List<Map<String, dynamic>> allQRCodes = [];
      int from = 0;
      const int pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        // Исправленный запрос без вложенных связей
        final response = await _supabase
            .from('daily_qr_codes')
            .select('token, date, expires_at, used, ticket_id')
            .eq('used', false)
            .gte('date', startDate
            .toIso8601String()
            .split('T')
            .first)
            .lte('date', endDate
            .toIso8601String()
            .split('T')
            .first)
            .order('date', ascending: true)
            .range(from, from + pageSize - 1);

        if (response.isNotEmpty) {
          allQRCodes.addAll(List<Map<String, dynamic>>.from(response));

          if (response.length < pageSize) {
            hasMore = false;
          } else {
            from += pageSize;
          }
        } else {
          hasMore = false;
        }
      }

      if (allQRCodes.isEmpty) {
        print('Нет QR кодов для загрузки');
        return [];
      }

      print('Загружено QR кодов: ${allQRCodes.length}');

      // Получаем ID талонов из QR кодов
      final ticketIds = allQRCodes
          .map((qr) => qr['ticket_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      if (ticketIds.isEmpty) {
        print('Нет ticket_id в QR кодах');
        return [];
      }

      // Получаем информацию о талонах
      final ticketsResponse = await _supabase
          .from('tickets')
          .select('id, student_id')
          .inFilter('id', ticketIds);

      // Получаем ID студентов из талонов
      final studentIds = ticketsResponse
          .map((t) => t['student_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      // Получаем информацию о студентах
      final Map<String, Map<String, dynamic>> studentProfiles = {};

      if (studentIds.isNotEmpty) {
        final studentsResponse = await _supabase
            .from('profiles')
            .select('id, full_name, student_group, student_speciality')
            .inFilter('id', studentIds);

        for (var student in studentsResponse) {
          studentProfiles[student['id'].toString()] = {
            'full_name': student['full_name'] ?? '',
            'group': student['student_group'] ?? '',
            'speciality': student['student_speciality'] ?? '',
          };
        }
      }

      // Создаем мапу ticket_id -> student_id
      final Map<String, String> ticketToStudent = {};
      for (var ticket in ticketsResponse) {
        ticketToStudent[ticket['id'].toString()] =
            ticket['student_id'].toString();
      }

      // Формируем полные данные QR кодов
      final List<Map<String, dynamic>> qrCodes = [];

      for (var qr in allQRCodes) {
        final ticketId = qr['ticket_id']?.toString();
        final studentId = ticketToStudent[ticketId];
        final studentInfo = studentProfiles[studentId] ?? {
          'full_name': 'Неизвестный студент',
          'group': 'Не указана',
          'speciality': 'Не указана',
        };

        qrCodes.add({
          'token': qr['token'],
          'student': studentInfo['full_name'],
          'group': studentInfo['group'],
          'speciality': studentInfo['speciality'],
          'date': qr['date'],
          'expires': DateFormat('dd.MM.yyyy HH:mm').format(
              DateTime.parse(qr['expires_at'])),
          'used': qr['used'] ?? false,
          'ticket_id': ticketId,
        });
      }

      print('Сформировано QR кодов: ${qrCodes.length}');
      return qrCodes;
    } catch (e) {
      debugPrint('Ошибка загрузки QR кодов: $e');
      return [];
    }
  }

  // Методы для работы со студентами
  Future<void> _addStudent() async {
    setState(() {
      _isEditing = false;
      _editingStudent = null;
      _fullNameController.clear();
      _emailController.clear();
      _groupController.clear();
      _specialityController.clear();
    });

    await _showStudentDialog();
  }

  Future<void> _updateStudentProfile({
    required String studentId,
    required String fullName,
    required String email,
    required String studentGroup,
    required String studentSpeciality,
    required String iin,
    required String category,
    required String phone,
    required String dateOfBirth,
    required String username,
  }) async {
    try {
      await _supabase.rpc(
        'admin_update_student_profile',
        params: {
          'p_student_id': studentId,
          'p_full_name': fullName,
          'p_email': email,
          'p_student_group': studentGroup,
          'p_student_speciality': studentSpeciality,
          'p_iin': iin,
          'p_category': category,
          'p_phone': phone,
          'p_date_of_birth': dateOfBirth,
          'p_username': username,
        },
      );

      debugPrint('Профиль студента успешно обновлен');
    } catch (e) {
      debugPrint('Ошибка обновления профиля: $e');
      rethrow;
    }
  }

  Future<void> _editStudent(Map<String, dynamic> student) async {
    try {
      // Сначала загрузим полные данные студента
      final fullStudentData = await _supabase
          .from('profiles')
          .select('*')
          .eq('id', student['id'])
          .single();

      debugPrint('Данные студента для редактирования:');
      debugPrint('ID: ${fullStudentData['id']}');
      debugPrint('ФИО: ${fullStudentData['full_name']}');
      debugPrint('Email: ${fullStudentData['email']}');
      debugPrint('Группа: ${fullStudentData['student_group']}');
      debugPrint('Специальность: ${fullStudentData['student_speciality']}');
      debugPrint('ИИН: ${fullStudentData['iin']}');
      debugPrint('Категория: ${fullStudentData['category']}');
      debugPrint('Телефон: ${fullStudentData['phone']}');
      debugPrint('Дата рождения: ${fullStudentData['date_of_birth']}');

      // Заполните контроллеры данными
      setState(() {
        _isEditing = true;
        _editingStudent = fullStudentData;
        _fullNameController.text = fullStudentData['full_name'] ?? '';
        _emailController.text = fullStudentData['email'] ?? '';
        _groupController.text = fullStudentData['student_group'] ?? '';
        _specialityController.text =
            fullStudentData['student_speciality'] ?? '';
        _iinController.text = fullStudentData['iin'] ?? '';
        _categoryController.text = fullStudentData['category'] ?? '';
        _phoneController.text = fullStudentData['phone'] ?? '';
        _birthDateController.text = fullStudentData['date_of_birth'] ?? '';
      });

      await _showStudentDialog();
    } catch (e) {
      debugPrint('Ошибка загрузки данных студента: $e');
      _showSnackBar('Ошибка загрузки данных студента', isError: true);
    }
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => _isLoading = true);

      final fullName = _fullNameController.text.trim();
      final email = _emailController.text.trim();
      final group = _groupController.text.trim();
      final speciality = _specialityController.text.trim();
      final iin = _iinController.text.trim();
      final category = _categoryController.text.trim();
      final phone = _phoneController.text.trim();
      final birthDate = _birthDateController.text.trim();

      final username = _generateUsernameFromFIO(fullName);
      final password = _generateSixDigitPassword();

      debugPrint('=== ДАННЫЕ ДЛЯ СОЗДАНИЯ СТУДЕНТА ===');
      debugPrint('ФИО: $fullName');
      debugPrint('Email: $email');
      debugPrint('Группа: $group');
      debugPrint('Специальность: $speciality');
      debugPrint('ИИН: $iin');
      debugPrint('Категория: $category');
      debugPrint('Телефон: $phone');
      debugPrint('Дата рождения: $birthDate');
      debugPrint('Username: $username');
      debugPrint('Пароль: $password');
      debugPrint('====================================');

      if (_isEditing && _editingStudent != null) {
        await _updateStudentProfile(
          studentId: _editingStudent!['id'],
          fullName: _fullNameController.text,
          email: _emailController.text,
          studentGroup: _groupController.text,
          studentSpeciality: _specialityController.text,
          iin: _iinController.text,
          category: _categoryController.text,
          phone: _phoneController.text,
          dateOfBirth: _birthDateController.text,
          username: username,
        );

        _showSnackBar('Студент успешно обновлен');
      } else {
        const supabaseUrl = 'https://kofbizzblfbopsahanby.supabase.co';
        const serviceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtvZmJpenpibGZib3BzYWhhbmJ5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NzAwMzA2NiwiZXhwIjoyMDgyNTc5MDY2fQ.6gFNrBTdZpRiw6puEf94Gq328-4Kckao78-J8v1dgbk'; // ЗАМЕНИТЕ!

        // СОЗДАЕМ ПОЛЬЗОВАТЕЛЯ ЧЕРЕЗ ADMIN API
        final createUserResponse = await http.post(
          Uri.parse('$supabaseUrl/auth/v1/admin/users'),
          headers: {
            'Content-Type': 'application/json',
            'apikey': serviceRoleKey,
            'Authorization': 'Bearer $serviceRoleKey',
          },
          body: jsonEncode({
            'email': email,
            'password': password,
            'email_confirm': true,
            'user_metadata': {
              'full_name': fullName,
              'role': 'student',
              'student_group': group,
              'student_speciality': speciality,
              'iin': iin,
              'category': category,
              'phone': phone,
              'date_of_birth': birthDate.isNotEmpty ? birthDate : null,
              'username': username,
            },
          }),
        );

        debugPrint(
            'Статус создания пользователя: ${createUserResponse.statusCode}');
        debugPrint('Ответ: ${createUserResponse.body}');

        if (createUserResponse.statusCode != 200) {
          throw Exception(
              'Ошибка создания пользователя: ${createUserResponse.body}');
        }

        final userData = jsonDecode(createUserResponse.body);
        final userId = userData['id'] as String;

        debugPrint('Пользователь создан. ID: $userId');

        // Ждем 2 секунды, чтобы профиль мог создаться автоматически
        debugPrint('Ожидание создания профиля...');
        await Future.delayed(const Duration(seconds: 2));

        // ПРОВЕРЯЕМ И ОБНОВЛЯЕМ ПРОФИЛЬ
        try {
          // Сначала проверяем, существует ли профиль
          final existingProfile = await _supabase
              .from('profiles')
              .select('*')
              .eq('id', userId)
              .maybeSingle();

          if (existingProfile != null) {
            debugPrint('Профиль уже существует. Данные:');
            debugPrint('ID: ${existingProfile['id']}');
            debugPrint('Email: ${existingProfile['email']}');
            debugPrint('ФИО: ${existingProfile['full_name']}');
            debugPrint('Группа: ${existingProfile['student_group']}');
            debugPrint(
                'Специальность: ${existingProfile['student_speciality']}');

            // Обновляем все поля
            debugPrint('Начинаем обновление профиля...');

            final updateData = {
              'full_name': fullName,
              'email': email,
              'username': username,
              'student_group': group.isNotEmpty ? group : null,
              'student_speciality': speciality.isNotEmpty ? speciality : null,
              'iin': iin.isNotEmpty ? iin : null,
              'category': category.isNotEmpty ? category : null,
              'phone': phone.isNotEmpty ? phone : null,
              'date_of_birth': birthDate.isNotEmpty ? birthDate : null,
              'role': 'student',
              'updated_at': DateTime.now().toIso8601String(),
            };

            debugPrint('Данные для обновления: $updateData');

            final updateResponse = await _supabase
                .from('profiles')
                .update(updateData)
                .eq('id', userId);

            debugPrint('Профиль обновлен');

            // Проверяем, что данные обновились
            final updatedProfile = await _supabase
                .from('profiles')
                .select('*')
                .eq('id', userId)
                .single();

            debugPrint('Проверка обновленных данных:');
            debugPrint('Группа: ${updatedProfile['student_group']}');
            debugPrint(
                'Специальность: ${updatedProfile['student_speciality']}');
            debugPrint('ИИН: ${updatedProfile['iin']}');
          } else {
            debugPrint('Профиль не существует, создаем новый...');

            // Создаем новый профиль
            final insertData = {
              'id': userId,
              'email': email,
              'full_name': fullName,
              'username': username,
              'student_group': group.isNotEmpty ? group : null,
              'student_speciality': speciality.isNotEmpty ? speciality : null,
              'iin': iin.isNotEmpty ? iin : null,
              'category': category.isNotEmpty ? category : null,
              'phone': phone.isNotEmpty ? phone : null,
              'date_of_birth': birthDate.isNotEmpty ? birthDate : null,
              'role': 'student',
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            };

            debugPrint('Данные для вставки: $insertData');

            await _supabase.from('profiles').insert(insertData);
            debugPrint('Профиль создан');
          }
        } catch (e) {
          debugPrint('Ошибка при работе с профилем: $e');

          // Пробуем альтернативный способ
          debugPrint('Пробуем альтернативный способ...');

          try {
            // Используем upsert
            await _supabase
                .from('profiles')
                .upsert({
              'id': userId,
              'email': email,
              'full_name': fullName,
              'username': username,
              'student_group': group,
              'student_speciality': speciality,
              'iin': iin,
              'category': category,
              'phone': phone,
              'date_of_birth': birthDate.isNotEmpty ? birthDate : null,
              'role': 'student',
            }, onConflict: 'id');

            debugPrint('Профиль создан/обновлен через upsert');
          } catch (upsertError) {
            debugPrint('Ошибка upsert: $upsertError');
            throw Exception('Не удалось создать профиль: $upsertError');
          }
        }

        // Проверяем финальный результат
        debugPrint('Проверяем финальные данные в базе...');

        final finalCheck = await _supabase
            .from('profiles')
            .select('''
            id, 
            email, 
            full_name, 
            username, 
            student_group, 
            student_speciality, 
            iin, 
            category, 
            phone, 
            date_of_birth
          ''')
            .eq('id', userId)
            .single();

        debugPrint('ФИНАЛЬНЫЕ ДАННЫЕ ПРОФИЛЯ:');
        debugPrint('ID: ${finalCheck['id']}');
        debugPrint('Email: ${finalCheck['email']}');
        debugPrint('ФИО: ${finalCheck['full_name']}');
        debugPrint('Username: ${finalCheck['username']}');
        debugPrint('Группа: ${finalCheck['student_group']}');
        debugPrint('Специальность: ${finalCheck['student_speciality']}');
        debugPrint('ИИН: ${finalCheck['iin']}');
        debugPrint('Категория: ${finalCheck['category']}');
        debugPrint('Телефон: ${finalCheck['phone']}');
        debugPrint('Дата рождения: ${finalCheck['date_of_birth']}');
      }

      if (mounted) {
        Navigator.of(context).pop();
        _showSnackBar('Студент создан! Логин: $email, Пароль: $password');

        // Обновляем списки
        await _loadAllStudents();
        await _loadAvailableStudents();
      }
    } catch (e) {
      debugPrint('=== КРИТИЧЕСКАЯ ОШИБКА ===');
      debugPrint('Ошибка: $e');
      debugPrint('Stack trace: ${e.toString()}');

      if (mounted) {
        _showSnackBar('Ошибка: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _generateUsernameFromFIO(String fullName) {
    debugPrint('Генерация username из: "$fullName"');

    // Расширенная таблица транслитерации: русские + казахские буквы.
    const Map<String, String> translit = {
      'а': 'a', 'ә': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ғ': 'gh', 'д': 'd',
      'е': 'e', 'ё': 'e', 'ж': 'zh', 'з': 'z', 'и': 'i', 'і': 'i', 'й': 'y',
      'к': 'k', 'қ': 'q', 'л': 'l', 'м': 'm', 'н': 'n', 'ң': 'ng', 'о': 'o',
      'ө': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ұ': 'u',
      'ү': 'u', 'ф': 'f', 'х': 'kh', 'һ': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh',
      'щ': 'shch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
      ' ': '_', '-': '_'
    };

    String transliterateChar(String ch) {
      final lower = ch.toLowerCase();
      return translit[lower] ?? lower;
    }

    // Разбиваем по пробелам/табуляциям/прочим разделителям
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();

    final List<String> processed = [];

    for (final part in parts) {
      final buffer = StringBuffer();
      for (var i = 0; i < part.length; i++) {
        buffer.write(transliterateChar(part[i]));
      }
      var s = buffer.toString();

      // Удаляем всё, что не a-z, цифры или подчеркивание
      s = s.replaceAll(RegExp(r'[^a-z0-9_]', caseSensitive: false), '');

      // Удаляем повторяющиеся подчеркивания
      while (s.contains('__')) s = s.replaceAll('__', '_');

      // Обрезаем ведущие/замыкающие подчеркивания
      s = s.replaceAll(RegExp(r'^_+|_+$'), '');

      if (s.isEmpty) continue;

      // Делаем первую букву заглавной, остальные — строчными,
      // чтобы получить вид: Abai_Abillgazy
      final lower = s.toLowerCase();
      final capitalized = lower.length == 1
          ? lower.toUpperCase()
          : '${lower[0].toUpperCase()}${lower.substring(1)}';

      processed.add(capitalized);
    }

    var result = processed.join('_');

    // Если ничего не получилось — fallback
    if (result.isEmpty) {
      result = 'student${DateTime.now().millisecondsSinceEpoch % 10000}';
    }

    debugPrint('Сгенерирован username: "$result"');
    return result;
  }

  String _generateSixDigitPassword() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<void> _deleteStudent(Map<String, dynamic> student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Удаление студента'),
            content: Text(
                'Вы уверены, что хотите удалить студента ${student['full_name']}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                    'Удалить', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        setState(() => _isLoading = true);

        // Используйте функцию для удаления
        await _supabase
            .rpc('admin_delete_profile', params: {
          'p_profile_id': student['id'],
        });

        _showSnackBar('Студент успешно удален');

        await _loadAllStudents();
        await _loadAvailableStudents();
      } catch (e) {
        debugPrint('Ошибка удаления студента: $e');
        _showSnackBar('Ошибка удаления: ${e.toString()}', isError: true);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showStudentDialog() async {
    await showDialog(
      context: context,
      builder: (context) =>
          StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(_isEditing
                    ? 'Редактировать студента'
                    : 'Добавить студента'),
                content: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: _fullNameController,
                          decoration: const InputDecoration(
                            labelText: 'ФИО *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value
                                .trim()
                                .isEmpty) {
                              return 'Введите ФИО';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value
                                .trim()
                                .isEmpty) {
                              return 'Введите email';
                            }
                            if (!value.contains('@')) {
                              return 'Введите корректный email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _iinController,
                          decoration: const InputDecoration(
                            labelText: 'ИИН *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value
                                .trim()
                                .isEmpty) {
                              return 'Введите ИИН';
                            }
                            if (value.length != 12) {
                              return 'ИИН должен содержать 12 цифр';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _groupController,
                          decoration: const InputDecoration(
                            labelText: 'Группа *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value
                                .trim()
                                .isEmpty) {
                              return 'Введите группу';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _specialityController,
                          decoration: const InputDecoration(
                            labelText: 'Специальность',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _categoryController,
                          decoration: const InputDecoration(
                            labelText: 'Категория',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Номер телефона',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _birthDateController,
                          decoration: InputDecoration(
                            labelText: 'Дата рождения',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today),
                              onPressed: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) {
                                  _birthDateController.text =
                                      DateFormat('yyyy-MM-dd').format(date);
                                  setState(() {}); // Обновляем состояние виджета
                                }
                              },
                            ),
                          ),
                          readOnly: true,
                        ),
                        const SizedBox(height: 16),
                        if (!_isEditing)
                          Text(
                            'Для нового студента будет сгенерирован случайный 6-значный пароль',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveStudent,
                    child: _isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Сохранить'),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await _supabase.auth.signOut();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      _showSnackBar('Ошибка выхода: ${e.toString()}', isError: true);
    }
  }

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );

    if (date != null) {
      setState(() {
        _selectedStartDate = date;
        _startDateController.text = DateFormat('dd.MM.yyyy').format(date);
        _selectedPeriod = 'custom';
      });
    }
  }

  Future<void> _selectEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate ??
          (_selectedStartDate ?? DateTime.now()).add(const Duration(days: 30)),
      firstDate: _selectedStartDate ?? DateTime(2023),
      lastDate: DateTime(2030),
    );

    if (date != null) {
      setState(() {
        _selectedEndDate = date;
        _endDateController.text = DateFormat('dd.MM.yyyy').format(date);
        _selectedPeriod = 'custom';
      });
    }
  }

  Future<void> _selectDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange ?? DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      ),
    );

    if (range != null) {
      setState(() => _selectedDateRange = range);
      await _loadCanteenStats();
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    return '?';
  }

  Widget _buildStudentsTab() {
    final filteredStudents = _students.where((student) {
      final name = (student['full_name'] ?? '').toString().toLowerCase();
      final group = (student['student_group'] ?? '').toString().toLowerCase();
      final email = (student['email'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) ||
          group.contains(_searchQuery) ||
          email.contains(_searchQuery);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск по ФИО, группе или email...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme
                        .of(context)
                        .colorScheme
                        .surfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _addStudent,
                icon: const Icon(Icons.person_add),
                label: const Text('Добавить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Chip(
                label: Text('Всего: ${_students.length}'),
                backgroundColor: AppColors.primary.withOpacity(0.1),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text('Фильтр: ${filteredStudents.length}'),
                backgroundColor: Colors.blue.withOpacity(0.1),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadAllStudents,
                tooltip: 'Обновить список',
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Expanded(
          child: filteredStudents.isEmpty
              ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('Студенты не найдены', style: TextStyle(fontSize: 16)),
              ],
            ),
          )
              : ListView.builder(
            itemCount: filteredStudents.length,
            itemBuilder: (context, index) {
              final student = filteredStudents[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(_getInitials(student['full_name'] ?? '')),
                  ),
                  title: Text(
                    student['full_name'] ?? 'Без имени',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Группа: ${student['student_group'] ?? 'Нет группы'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Специальность: ${student['student_speciality'] ??
                            'Не указана'}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        student['email'] ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showStudentActions(student),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionsTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Text(
              'Отчеты по посещаемости секций и кружков',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // Выбор типа секции
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Тип секции',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildSectionTypeChip('Спортивные секции', 'sport'),
                        _buildSectionTypeChip('Кружки', 'club'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Выбор конкретной секции (если не выбрано "Все")
            if (_selectedSectionTypeReport != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Выберите секцию',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedSectionIdReport,
                        decoration: InputDecoration(
                          labelText: 'Выберите секцию',
                          border: OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [
                          DropdownMenuItem<String>(
                            value: null,
                            child: Text('Все ${_selectedSectionTypeReport == 'sport' ? 'спортивные секции' : 'кружки'}'),
                          ),
                          ...(_selectedSectionTypeReport == 'sport'
                              ? _sportSectionsForReport
                              : _clubSectionsForReport)
                              .map((section) {
                            return DropdownMenuItem<String>(
                              value: section['id'].toString(),
                              child: Text(
                                '${section['title']} (${section['coach_name'] ?? 'Без тренера'})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedSectionIdReport = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Выбор даты
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выберите дату',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selectReportDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedReportDate != null
                                    ? DateFormat('dd.MM.yyyy').format(_selectedReportDate!)
                                    : 'Выберите дату',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _selectedReportDate != null
                                      ? Colors.black
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Кнопка загрузки отчета
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoadingSectionReport ? null : _loadSectionAttendanceReport,
                icon: _isLoadingSectionReport
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.search),
                label: Text(_isLoadingSectionReport ? 'Загрузка...' : 'Загрузить отчет'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Результаты отчета
            if (_sectionAttendanceReport.isNotEmpty) ...[
              Text(
                'Результаты отчета (${_sectionAttendanceReport.length} записей)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Посещаемость за ${DateFormat('dd.MM.yyyy').format(_selectedReportDate!)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _isExporting ? null : _exportSectionAttendanceReport,
                            icon: _isExporting
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Icon(Icons.download),
                            label: Text(_isExporting ? 'Экспорт...' : 'Экспорт в Excel'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Таблица результатов
                      Container(
                        height: 400,
                        child: Scrollbar(
                          child: ListView.builder(
                            itemCount: _sectionAttendanceReport.length,
                            itemBuilder: (context, index) {
                              final record = _sectionAttendanceReport[index];
                              final status = record['attendance_status']?.toString() ?? '';

                              Color statusColor;
                              String statusText;

                              switch (status) {
                                case 'present':
                                  statusColor = Colors.green;
                                  statusText = 'Присутствовал';
                                  break;
                                case 'absent':
                                  statusColor = Colors.red;
                                  statusText = 'Отсутствовал';
                                  break;
                                case 'excused':
                                  statusColor = Colors.orange;
                                  statusText = 'По ув. причине';
                                  break;
                                default:
                                  statusColor = Colors.grey;
                                  statusText = 'Неизвестно';
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(12),
                                  leading: CircleAvatar(
                                    backgroundColor: statusColor.withOpacity(0.1),
                                    child: Icon(
                                      status == 'present'
                                          ? Icons.check_circle
                                          : status == 'absent'
                                          ? Icons.cancel
                                          : Icons.medical_services,
                                      color: statusColor,
                                    ),
                                  ),
                                  title: Text(
                                    record['full_name']?.toString() ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Группа: ${record['student_group'] ?? ''}'),
                                      Text('Секция: ${record['section_title'] ?? ''}'),
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: statusColor.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // Сводная статистика
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),

                      Text(
                        'Сводная статистика',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildAttendanceStatCard(
                            'Присутствовали',
                            _sectionAttendanceReport.where((r) => r['attendance_status'] == 'present').length,
                            Colors.green,
                          ),
                          _buildAttendanceStatCard(
                            'Отсутствовали',
                            _sectionAttendanceReport.where((r) => r['attendance_status'] == 'absent').length,
                            Colors.red,
                          ),
                          _buildAttendanceStatCard(
                            'По ув. причине',
                            _sectionAttendanceReport.where((r) => r['attendance_status'] == 'excused').length,
                            Colors.orange,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_sectionAttendanceReport.isEmpty && !_isLoadingSectionReport) ...[
              const SizedBox(height: 40),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.sports_outlined,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Загрузите отчет для просмотра данных',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

// Вспомогательный метод для чипов выбора типа секции
  Widget _buildSectionTypeChip(String label, String value) {
    final isSelected = _selectedSectionTypeReport == value;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedSectionTypeReport = selected ? value : null;
          _selectedSectionIdReport = null;
          _sectionAttendanceReport.clear();
        });
      },
      selectedColor: AppColors.primary.withOpacity(0.2),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : Colors.black,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

// Вспомогательный метод для карточек статистики
  Widget _buildAttendanceStatCard(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTicketsTab() {
    // Если идет загрузка, показываем индикатор
    if (_isLoadingTickets && _availableStudents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Загрузка студентов (Free Payer)...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    final searchQuery = _ticketSearchController.text.trim().toLowerCase();

    // Фильтрация студентов
    List<Map<String, dynamic>> filteredStudents;

    if (searchQuery.isEmpty) {
      // Если поиск пустой, показываем первые 100 студентов
      filteredStudents = _availableStudents.take(100).toList();
    } else {
      // Если есть поисковый запрос, фильтруем по нему
      filteredStudents = _availableStudents.where((student) {
        final name = (student['full_name'] ?? '').toString().toLowerCase();
        final group = (student['student_group'] ?? '').toString().toLowerCase();
        final category = (student['category'] ?? '').toString().toLowerCase();
        return name.contains(searchQuery) ||
            group.contains(searchQuery) ||
            category.contains(searchQuery);
      }).toList();

      // Ограничиваем результаты поиска 200 элементами
      filteredStudents = filteredStudents.take(200).toList();
    }

    // Учет клавиатуры
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Заголовок с информацией
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'В этой вкладке отображаются только студенты с категорией "Free Payer"',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[800],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Поиск
          TextField(
            controller: _ticketSearchController,
            decoration: InputDecoration(
              hintText: 'Поиск по ФИО, группе или категории...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceVariant,
            ),
            onChanged: (v) => setState(() {}),
          ),

          const SizedBox(height: 16),

          if (_selectedStudent == null) ...[
            // Информация о количестве студентов
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Chip(
                    label: Text('Free Payer: ${_availableStudents.length}'),
                    backgroundColor: Colors.green.withOpacity(0.1),
                  ),
                  const SizedBox(width: 8),
                  if (searchQuery.isNotEmpty)
                    Chip(
                      label: Text('Найдено: ${filteredStudents.length}'),
                      backgroundColor: Colors.blue.withOpacity(0.1),
                    ),
                  const Spacer(),
                  // Кнопка для переключения категории
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.filter_alt),
                    tooltip: 'Фильтры и действия',
                    onSelected: (value) async {
                      if (value == 'refresh') {
                        await _loadAvailableStudents();
                      } else if (value == 'show_all') {
                        await _showAllStudentsInTickets();
                      } else if (value == 'change_category') {
                        await _showChangeCategoryDialog();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'refresh',
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 20),
                            SizedBox(width: 8),
                            Text('Обновить список'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'show_all',
                        child: Row(
                          children: [
                            Icon(Icons.people, size: 20),
                            SizedBox(width: 8),
                            Text('Показать всех студентов'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'change_category',
                        child: Row(
                          children: [
                            Icon(Icons.category, size: 20),
                            SizedBox(width: 8),
                            Text('Изменить категорию студента'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (filteredStudents.isEmpty)
              _buildEmptyState(searchQuery.isNotEmpty)
            else
            // Список студентов
              _buildStudentsListView(filteredStudents),
          ] else ...[
            // Карточка выбранного студента с деталями категории
            _buildSelectedStudentCard(),

            const SizedBox(height: 24),

            // Форма активации талона
            _buildTicketActivationForm(),
          ],
        ],
      ),
    );
  }

  // Метод для отображения состояния, когда нет студентов
  Widget _buildEmptyState(bool isSearching) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.people_outline,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            isSearching
                ? 'Студенты не найдены'
                : 'Нет студентов с категорией "Free Payer"',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (!isSearching)
            Text(
              'Измените категорию студентов на "Free Payer" в профиле',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 16),
          if (!isSearching)
            ElevatedButton.icon(
              onPressed: () => _showChangeCategoryDialog(),
              icon: const Icon(Icons.category),
              label: const Text('Изменить категории'),
            ),
        ],
      ),
    );
  }

// Метод для отображения выбранного студента
  Widget _buildSelectedStudentCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(_getInitials(_selectedStudent!['full_name'] ?? '')),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedStudent!['full_name'] ?? 'Без имени',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Группа: ${_selectedStudent!['student_group'] ?? 'Нет группы'}'),
                      Text('Специальность: ${_selectedStudent!['student_speciality'] ?? 'Не указана'}'),
                      Text(
                        'Категория: ${_selectedStudent!['category'] ?? 'Не указана'}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedStudent = null),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Кнопка для изменения категории
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _changeSelectedStudentCategory(),
                icon: const Icon(Icons.category, size: 18),
                label: const Text('Изменить категорию'),
              ),
            ),
          ],
        ),
      ),
    );
  }

// Метод для отображения списка студентов
  Widget _buildStudentsListView(List<Map<String, dynamic>> students) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: students.length,
        itemBuilder: (context, index) {
          final student = students[index];
          return _buildStudentCard(student);
        },
      ),
    );
  }

// Диалог для изменения категории студента
  Future<void> _showChangeCategoryDialog() async {
    final selectedStudent = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        final TextEditingController searchController = TextEditingController();
        List<Map<String, dynamic>> filteredStudents = _students;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Изменить категорию студента'),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        hintText: 'Поиск студента...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final query = value.toLowerCase();
                        setState(() {
                          filteredStudents = _students.where((student) {
                            final name = (student['full_name'] ?? '').toString().toLowerCase();
                            final group = (student['student_group'] ?? '').toString().toLowerCase();
                            return name.contains(query) || group.contains(query);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: filteredStudents.isEmpty
                          ? const Center(child: Text('Студенты не найдены'))
                          : ListView.builder(
                        itemCount: filteredStudents.length,
                        itemBuilder: (context, index) {
                          final student = filteredStudents[index];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(_getInitials(student['full_name'] ?? '')),
                            ),
                            title: Text(student['full_name'] ?? 'Без имени'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Группа: ${student['student_group'] ?? 'Нет группы'}'),
                                Text('Категория: ${student['category'] ?? 'Не указана'}'),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (category) async {
                                try {
                                  await _updateStudentCategory(
                                    student['id'].toString(),
                                    category,
                                  );
                                  Navigator.pop(context, student);
                                } catch (e) {
                                  _showSnackBar('Ошибка: ${e.toString()}', isError: true);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'Free Payer',
                                  child: Text('Free Payer'),
                                ),
                                const PopupMenuItem(
                                  value: 'Paid Payer',
                                  child: Text('Paid Payer'),
                                ),
                                const PopupMenuItem(
                                  value: 'Grant Payer',
                                  child: Text('Grant Payer'),
                                ),
                                const PopupMenuItem(
                                  value: 'Other',
                                  child: Text('Другая категория'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedStudent != null) {
      _showSnackBar('Категория студента обновлена');
    }
  }

// Метод для изменения категории выбранного студента
  Future<void> _changeSelectedStudentCategory() async {
    if (_selectedStudent == null) return;

    final category = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изменить категорию'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Студент: ${_selectedStudent!['full_name']}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            const Text('Выберите новую категорию:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'Free Payer'),
            child: const Text('Free Payer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Paid Payer'),
            child: const Text('Paid Payer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Grant Payer'),
            child: const Text('Grant Payer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Other'),
            child: const Text('Другая'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (category != null && category.isNotEmpty) {
      try {
        await _updateStudentCategory(_selectedStudent!['id'].toString(), category);
        _showSnackBar('Категория изменена на: $category');

        // Обновляем выбранного студента
        final updatedStudent = {..._selectedStudent!, 'category': category};
        setState(() => _selectedStudent = updatedStudent);

      } catch (e) {
        _showSnackBar('Ошибка изменения категории: ${e.toString()}', isError: true);
      }
    }
  }

// Метод для временного отображения всех студентов (для отладки)
  Future<void> _showAllStudentsInTickets() async {
    try {
      setState(() => _isLoadingTickets = true);

      // Загружаем всех студентов без фильтра по категории
      List<Map<String, dynamic>> allStudents = [];
      int offset = 0;
      const int pageSize = 500;

      while (true) {
        final response = await _supabase
            .from('profiles')
            .select('id, full_name, student_group, student_speciality, category')
            .eq('role', 'student')
            .order('full_name')
            .range(offset, offset + pageSize - 1)
            .limit(pageSize);

        if (response.isEmpty) break;

        allStudents.addAll(List<Map<String, dynamic>>.from(response));
        offset += pageSize;

        if (response.length == pageSize) {
          await Future.delayed(const Duration(milliseconds: 30));
        }
      }

      // Получаем активные талоны
      final activeTickets = await _supabase
          .from('tickets')
          .select('student_id')
          .eq('is_active', true)
          .limit(3000);

      final Set<String> studentsWithActiveTickets = activeTickets
          .map<String>((t) => t['student_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final List<Map<String, dynamic>> students = allStudents.map((student) {
        return {
          ...student,
          'has_active_ticket': studentsWithActiveTickets.contains(student['id'].toString()),
        };
      }).toList();

      setState(() {
        _availableStudents = students;
        _isLoadingTickets = false;
      });

      _showSnackBar('Показаны все студенты (${students.length})');

    } catch (e) {
      debugPrint('Ошибка загрузки всех студентов: $e');
      setState(() => _isLoadingTickets = false);
      _showSnackBar('Ошибка загрузки: ${e.toString()}', isError: true);
    }
  }

// Метод для создания карточки студента
  Widget _buildStudentCard(Map<String, dynamic> student) {
    final hasActiveTicket = student['has_active_ticket'] == true;
    final category = student['category'] ?? 'Не указана';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasActiveTicket
              ? Colors.orange.withOpacity(0.1)
              : AppColors.primary.withOpacity(0.1),
          child: Text(_getInitials(student['full_name'] ?? '')),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              student['full_name'] ?? 'Без имени',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Text(
              'Категория: $category',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Группа: ${student['student_group'] ?? 'Нет группы'}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        trailing: hasActiveTicket
            ? const Chip(
          label: Text('Есть талон'),
          backgroundColor: Colors.orange,
          labelStyle: TextStyle(color: Colors.white),
        )
            : const Icon(Icons.chevron_right),
        onTap: () {
          if (hasActiveTicket) {
            _showActiveTicketWarning(student);
          } else {
            setState(() => _selectedStudent = student);
          }
        },
      ),
    );
  }

// Метод для формы активации талона
  Widget _buildTicketActivationForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Выберите период действия:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),

            // Быстрые периоды
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPeriodChip('День', 'day'),
                _buildPeriodChip('Неделя', 'week'),
                _buildPeriodChip('Месяц', 'month'),
                _buildPeriodChip('Произвольный', 'custom'),
              ],
            ),

            // Кастомный период
            if (_selectedPeriod == 'custom') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startDateController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Дата начала',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: _selectStartDate,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _endDateController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Дата окончания',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: _selectEndDate,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // Кнопка активации
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _activateTicket,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.primary,
                ),
                child: const Text(
                  'АКТИВИРОВАТЬ ТАЛОН',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

// Вспомогательный метод для создания чипов периодов
  Widget _buildPeriodChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedPeriod == value,
      onSelected: (_) =>
          setState(() {
            _selectedPeriod = value;
            if (value != 'custom') {
              _selectedStartDate = null;
              _selectedEndDate = null;
              _startDateController.clear();
              _endDateController.clear();
            }
          }),
    );
  }

  Widget _buildReportsTab() {
    final studentDetails = List<Map<String, dynamic>>.from(
        _canteenStats['student_details'] ?? []);
    final hasMoreStudents = _canteenStats['has_more_students'] ?? false;
    final totalStudents = _canteenStats['total_students_count'] ??
        studentDetails.length;

    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Статистика посещаемости', style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _loadCanteenStats,
                          tooltip: 'Обновить',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Период: ${_canteenStats['period_start'] ??
                                ''} - ${_canteenStats['period_end'] ?? ''}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _selectDateRange,
                          icon: const Icon(Icons.date_range),
                          label: const Text('Изменить'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard(
                          'Всего студентов',
                          '${_canteenStats['total_students']}',
                          Icons.people,
                          Colors.blue,
                        ),
                        _buildStatCard(
                          'Средняя посещаемость',
                          '${_canteenStats['average_attendance']}%',
                          Icons.trending_up,
                          Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Экспорт отчетов', style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: _selectedExportType,
                      decoration: InputDecoration(
                        labelText: 'Тип отчета',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: _exportTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedExportType = value);
                        if (value != 'QR коды') {
                          _selectedQrPeriod = null;
                        }
                        if (value != 'По группам') {
                          _selectedGroup = null;
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    if (_selectedExportType == 'По группам') ...[
                      DropdownButtonFormField<String>(
                        value: _selectedGroup,
                        decoration: InputDecoration(
                          labelText: 'Выберите группу',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _availableGroups.map((group) {
                          return DropdownMenuItem(
                            value: group,
                            child: Text(group),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          setState(() => _selectedGroup = value);
                          if (value != null) {
                            await _loadGroupReport(value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ],

                    if (_selectedExportType == 'QR коды') ...[
                      DropdownButtonFormField<String>(
                        value: _selectedQrPeriod,
                        decoration: InputDecoration(
                          labelText: 'Период для QR кодов',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _qrPeriods.map((period) {
                          return DropdownMenuItem(
                            value: period,
                            child: Text(period),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setState(() => _selectedQrPeriod = value),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Примечание: Будет создан файл Excel с QR кодами',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isExporting ? null : _exportReport,
                            icon: _isExporting
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                                : const Icon(Icons.download),
                            label: _isExporting
                                ? const Text('Генерация...')
                                : const Text('Скачать отчет в Excel'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () async {
                              final directory = await getApplicationDocumentsDirectory();
                              final result = await OpenFile.open(
                                  directory.path);
                              if (result.type != ResultType.done) {
                                _showSnackBar(
                                    'Не удалось открыть папку', isError: true);
                              }
                            },
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Открыть папку с отчетами'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Отчеты сохраняются в формате Excel (.xlsx) и открываются в любом табличном редакторе',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Отчет по выбранной группе
          if (_selectedGroup != null &&
              _selectedExportType == 'По группам') ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Отчет по группе: $_selectedGroup',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _selectedGroup = null;
                                _groupReportData.clear();
                                _selectedGroupStats.clear();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_isGroupReportLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        if (_selectedGroupStats.isNotEmpty) ...[
                          Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment
                                    .spaceAround,
                                children: [
                                  _buildStatCard(
                                    'Специальность',
                                    _selectedGroupStats['speciality'] ??
                                        'Не указана',
                                    Icons.school,
                                    Colors.blue,
                                  ),
                                  _buildStatCard(
                                    'Студентов',
                                    '${_selectedGroupStats['student_count']}',
                                    Icons.people,
                                    Colors.green,
                                  ),
                                  _buildStatCard(
                                    'Талонов',
                                    '${_selectedGroupStats['total_tickets']}',
                                    Icons.confirmation_number,
                                    Colors.orange,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment
                                    .spaceAround,
                                children: [
                                  _buildStatCard(
                                    'Использовано дней',
                                    '${_selectedGroupStats['total_used_days']}',
                                    Icons.check_circle,
                                    Colors.green,
                                  ),
                                  _buildStatCard(
                                    'Неиспользовано дней',
                                    '${_selectedGroupStats['total_unused_days']}',
                                    Icons.cancel,
                                    Colors.red,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Таблица студентов группы
                          const Text('Студенты группы:', style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Container(
                            height: 300,
                            child: Scrollbar(
                              child: ListView.builder(
                                itemCount: _groupReportData.length,
                                itemBuilder: (context, index) {
                                  final student = _groupReportData[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 0),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: AppColors.primary
                                            .withOpacity(0.1),
                                        child: Text(_getInitials(
                                            student['student_name'] ?? '')),
                                      ),
                                      title: Text(student['student_name'] ??
                                          'Неизвестно'),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment
                                            .start,
                                        children: [
                                          Text(
                                              'Талонов: ${student['total_tickets']}'),
                                          Text(
                                              'Использовано дней: ${student['used_days']}'),
                                          Text(
                                              'Неиспользовано дней: ${student['unused_days']}'),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Детальная статистика по студентам ($totalStudents всего)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

          Container(
            height: 400,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: studentDetails.isEmpty
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        Icons.analytics_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Нет данных для отображения'),
                  ],
                ),
              )
                  : _buildVirtualizedDataTable(studentDetails),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVirtualizedDataTable(List<Map<String, dynamic>> data) {
    // Используем ListView.builder для виртуализации строк
    return Scrollbar(
      child: ListView.builder(
        itemCount: data.length,
        itemBuilder: (context, index) {
          final student = data[index];
          final attendance = student['attendance_rate'] ?? 0;

          return Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                // Колонка ФИО
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Tooltip(
                      message: student['full_name'] ?? '',
                      child: Text(
                        student['full_name'] ?? '',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),

                // Колонка Группа
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Text(
                      student['group'] ?? '',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),

                // Колонка Специальность
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Tooltip(
                      message: student['speciality'] ?? '',
                      child: Text(
                        student['speciality'] ?? '',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),

                // Колонка Посещено
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        '${student['used_days']}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),

                // Колонка Всего
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        '${student['total_days']}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),

                // Колонка Посещаемость
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: Colors.grey[300],
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: attendance / 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  color: attendance >= 80
                                      ? Colors.green
                                      : attendance >= 50
                                      ? Colors.orange
                                      : Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 35,
                          child: Text(
                            '$attendance%',
                            style: TextStyle(
                              fontSize: 10,
                              color: attendance >= 80
                                  ? Colors.green
                                  : attendance >= 50
                                  ? Colors.orange
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }


  Widget _buildStatCard(String title, String value, IconData icon,
      Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 30, color: color),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  void _showStudentActions(Map<String, dynamic> student) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Редактировать'),
                onTap: () {
                  Navigator.pop(context);
                  _editStudent(student);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                    'Удалить', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteStudent(student);
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code),
                title: const Text('Активировать талон'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedStudent = student;
                    _tabController.index = 1;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showActiveTicketWarning(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Активный талон'),
            content: Text(
                'У студента ${student['full_name']} уже есть активный талон. Продолжить?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _selectedStudent = student);
                },
                child: const Text('Продолжить'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingRole) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                'Проверка доступа...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Панель администратора'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) {
            // Ленивая загрузка при переключении вкладок
            if (index == 1 && !_availableStudentsLoaded) {
              _loadAvailableStudents();
            }
          },
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Студенты'),
            Tab(icon: Icon(Icons.confirmation_number), text: 'Талон'),
            Tab(icon: Icon(Icons.analytics), text: 'Отчеты'),
            Tab(icon: Icon(Icons.sports), text: 'Секции'), // Новый таб
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _loadInitialData,
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 20),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadInitialData,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          _buildStudentsTab(),
          _buildTicketsTab(),
          _buildReportsTab(),
          _buildSectionsTab(), // Новый таб
        ],
      ),
    );
  }
}