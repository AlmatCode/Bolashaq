import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart'; // Импорт Google Fonts
import '../core/theme.dart';

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key});

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen>
    with AutomaticKeepAliveClientMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _realtimeChannel;

  // Состояние
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Данные
  List<Map<String, dynamic>> _clubs = [];
  List<Map<String, dynamic>> _myApplications = [];
  Map<String, dynamic>? _selectedClub;

  // Поиск
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Статистика
  Map<String, int> _stats = {
    'total': 0,
    'approved': 0,
    'pending': 0,
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text);
      }
    });
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

      // Загружаем все кружки (клубы) из extended_sections
      final clubsResponse = await _supabase
          .from('extended_sections')
          .select('''
          id, title, description, coach_name, schedule, 
          location, capacity, current_members, type, category, 
          is_active, registration_open, requirements, equipment_needed,
          coach_id, room, building
        ''')
          .eq('type', 'club')
          .order('title');

      if (clubsResponse == null) {
        throw Exception('Не удалось загрузить данные кружков');
      }

      // Подсчитываем одобренные заявки для каждого кружка
      final allApprovedApps = await _supabase
          .from('section_applications')
          .select('section_id')
          .eq('status', 'approved');

      final countsMap = <String, int>{};
      if (allApprovedApps != null) {
        for (final app in allApprovedApps) {
          final sectionId = app['section_id'] as String?;
          if (sectionId != null) {
            countsMap[sectionId] = (countsMap[sectionId] ?? 0) + 1;
          }
        }
      }

      // Загружаем мои заявки
      final applicationsResponse = await _supabase
          .from('section_applications')
          .select('''
          id, section_id, applicant_id, status, applied_at, 
          reviewed_at, motivation, priority
        ''')
          .eq('applicant_id', user.id)
          .order('applied_at', ascending: false);

      // Получаем информацию о кружках для моих заявок
      final myApplicationsWithDetails = [];
      if (applicationsResponse != null) {
        for (final app in applicationsResponse) {
          final sectionId = app['section_id'] as String?;
          if (sectionId != null) {
            try {
              final clubInfo = await _supabase
                  .from('extended_sections')
                  .select('title, schedule, location, category')
                  .eq('id', sectionId)
                  .single()
                  .catchError((e) => null);

              if (clubInfo != null) {
                myApplicationsWithDetails.add({
                  ...app,
                  'sections': clubInfo,
                });
              }
            } catch (e) {
              debugPrint('Error loading club info: $e');
            }
          }
        }
      }

      // Обновляем данные
      final List<Map<String, dynamic>> clubsList = [];

      if (clubsResponse != null) {
        for (final club in clubsResponse) {
          final clubId = club['id'] as String? ?? '';
          final count = countsMap[clubId] ?? 0;

          clubsList.add({
            ...club,
            'applications_count': count,
          });
        }
      }

      // Подсчитываем статистику
      int approvedCount = 0;
      int pendingCount = 0;

      for (final app in myApplicationsWithDetails) {
        final status = app['status'] as String?;
        switch (status) {
          case 'approved':
            approvedCount++;
            break;
          case 'pending':
            pendingCount++;
            break;
        }
      }

      setState(() {
        _clubs = clubsList;
        _myApplications = List<Map<String, dynamic>>.from(myApplicationsWithDetails);
        _stats = {
          'total': clubsList.length,
          'approved': approvedCount,
          'pending': pendingCount,
        };
      });

      _setupRealtimeSubscription();
    } on PostgrestException catch (error) {
      debugPrint('Error loading clubs: ${error.message}');
      setState(() {
        _errorMessage = 'Ошибка базы данных: ${error.message}';
      });
    } catch (error) {
      debugPrint('Error loading clubs: $error');
      setState(() {
        _errorMessage = 'Не удалось загрузить данные. Проверьте подключение.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupRealtimeSubscription() {
    try {
      // Отменяем старую подписку, если есть
      _realtimeChannel?.unsubscribe();

      // Подписываемся на изменения в таблице заявок
      _realtimeChannel = _supabase
          .channel('clubs-updates')
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'section_applications',
        callback: (payload) {
          // Обновляем данные при любых изменениях в заявках
          if (mounted) {
            _loadData();
          }
        },
      )
          .subscribe();
    } catch (error) {
      debugPrint('Error setting up realtime subscription: $error');
    }
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/login');
    });
  }

  Future<void> _applyForClub(Map<String, dynamic> club) async {
    try {
      setState(() => _isSubmitting = true);

      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Проверяем существующую заявку
      final existingApp = await _supabase
          .from('section_applications')
          .select('id, status')
          .eq('applicant_id', user.id)
          .eq('section_id', club['id'])
          .maybeSingle();

      if (existingApp != null) {
        _showSnackBar('Вы уже подавали заявку на этот кружок');
        return;
      }

      // Проверяем, открыта ли регистрация
      final isRegistrationOpen = club['registration_open'] as bool? ?? true;
      if (!isRegistrationOpen) {
        _showSnackBar('Регистрация на этот кружок закрыта', isError: true);
        return;
      }

      // Проверяем активность кружка
      final isActive = club['is_active'] as bool? ?? true;
      if (!isActive) {
        _showSnackBar('Этот кружок неактивен', isError: true);
        return;
      }

      // Проверяем вместимость
      final currentMembers = club['current_members'] as int? ?? 0;
      final capacity = club['capacity'] as int? ?? 0;
      final hasCapacity = capacity == 0 || currentMembers < capacity;

      if (!hasCapacity) {
        _showSnackBar('Мест нет. Кружок заполнен.', isError: true);
        return;
      }

      // Создаем заявку
      await _supabase.from('section_applications').insert({
        'applicant_id': user.id,
        'section_id': club['id'],
        'status': 'pending',
        'applied_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      _showSnackBar('✅ Заявка подана успешно!');

      // Обновляем данные
      await _loadData();
    } on PostgrestException catch (error) {
      debugPrint('Error applying for club: ${error.message}');
      _showSnackBar('❌ Ошибка базы данных: ${error.message}', isError: true);
    } catch (error) {
      debugPrint('Error applying for club: $error');
      _showSnackBar('❌ Ошибка при подаче заявки', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.roboto()),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _cancelApplication(String applicationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Отменить заявку', style: GoogleFonts.roboto()),
        content: Text('Вы уверены, что хотите отменить заявку?', style: GoogleFonts.roboto()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Нет', style: GoogleFonts.roboto()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Да, отменить', style: GoogleFonts.roboto()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase
          .from('section_applications')
          .update({
        'status': 'cancelled',
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', applicationId);

      _showSnackBar('Заявка отменена');
      await _loadData();
    } catch (error) {
      debugPrint('Error canceling application: $error');
      _showSnackBar('Ошибка при отмене заявки', isError: true);
    }
  }

  void _showClubDetails(Map<String, dynamic> club) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ClubDetailsModal(
        club: club,
        myApplications: _myApplications,
        onApply: () => _applyForClub(club),
        isSubmitting: _isSubmitting,
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredClubs() {
    List<Map<String, dynamic>> filtered = _clubs;

    // Применяем поиск
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((club) {
        return (club['title'] as String?)?.toLowerCase().contains(query) == true ||
            (club['description'] as String?)?.toLowerCase().contains(query) == true ||
            (club['coach_name'] as String?)?.toLowerCase().contains(query) == true;
      }).toList();
    }

    return filtered;
  }

  // НОВЫЕ КАРТОЧКИ СТАТИСТИКИ
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              Text(
                value,
                style: GoogleFonts.roboto(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.roboto(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Фракции колледжа',
                      style: GoogleFonts.roboto(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      'Студенческие сообщества и объединения',
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Статистика в виде трех больших карточек
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Всего фракций',
                  _stats['total']?.toString() ?? '0',
                  Icons.library_books,
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Мои фракции',
                  _stats['approved']?.toString() ?? '0',
                  Icons.check_circle,
                  AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Заявки',
                  _stats['pending']?.toString() ?? '0',
                  Icons.pending_actions,
                  AppColors.warning,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Поиск
          SizedBox(
            height: 50,
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.roboto(),
              decoration: InputDecoration(
                hintText: 'Поиск фракций...',
                hintStyle: GoogleFonts.roboto(),
                prefixIcon: const Icon(Icons.search, size: 22),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClubCard(Map<String, dynamic> club) {
    final coachName = club['coach_name'] ?? 'Не назначен';
    final currentMembers = club['current_members'] as int? ?? 0;
    final capacity = club['capacity'] as int? ?? 0;
    final isActive = club['is_active'] as bool? ?? true;
    final isRegistrationOpen = club['registration_open'] as bool? ?? true;

    final hasCapacity = capacity == 0 || currentMembers < capacity;
    final canApply = isActive && isRegistrationOpen && hasCapacity;

    final myApplication = _myApplications.firstWhere(
          (app) => app['section_id'] == club['id'],
      orElse: () => <String, dynamic>{},
    );

    final hasApplied = myApplication.isNotEmpty;
    final status = myApplication['status'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
      child: InkWell(
        onTap: () => _showClubDetails(club),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок и статус
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.flag,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                club['title']?.toString() ?? 'Без названия',
                                style: GoogleFonts.roboto(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Неактивно',
                                  style: GoogleFonts.roboto(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Руководитель: $coachName',
                          style: GoogleFonts.roboto(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasApplied)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _getStatusColor(status)),
                      ),
                      child: Text(
                        _getStatusText(status),
                        style: GoogleFonts.roboto(
                          fontSize: 11,
                          color: _getStatusColor(status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Описание
              if (club['description'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    club['description'].toString(),
                    style: GoogleFonts.roboto(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              // Детали
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            club['schedule']?.toString() ?? 'Не указано',
                            style: GoogleFonts.roboto(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.people,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        capacity > 0
                            ? '$currentMembers/$capacity'
                            : '$currentMembers',
                        style: GoogleFonts.roboto(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Кнопка действия
              if (!hasApplied && canApply)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _applyForClub(club),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('Подать заявку', style: GoogleFonts.roboto()),
                  ),
                )
              else if (hasApplied && status == 'pending')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _cancelApplication(myApplication['id'] as String),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: AppColors.error),
                    ),
                    child: Text(
                      'Отменить заявку',
                      style: GoogleFonts.roboto(color: AppColors.error),
                    ),
                  ),
                )
              else if (!isRegistrationOpen)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        'Регистрация закрыта',
                        style: GoogleFonts.roboto(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                else if (!hasCapacity)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Нет свободных мест',
                          style: GoogleFonts.roboto(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyApplications() {
    if (_myApplications.isEmpty) return const SizedBox.shrink();

    final pendingApps = _myApplications.where((app) => app['status'] == 'pending').toList();
    final approvedApps = _myApplications.where((app) => app['status'] == 'approved').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pendingApps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text(
              'Заявки на рассмотрении',
              style: GoogleFonts.roboto(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...pendingApps.map((app) => _buildApplicationCard(app)),
        ],
        if (approvedApps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text(
              'Ваши фракции',
              style: GoogleFonts.roboto(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...approvedApps.map((app) => _buildApplicationCard(app)),
        ],
      ],
    );
  }

  Widget _buildApplicationCard(Map<String, dynamic> application) {
    final sections = application['sections'] ?? {};
    final sectionTitle = sections['title'] as String? ?? 'Неизвестная фракция';
    final status = application['status'] as String? ?? '';
    final appliedDate = application['applied_at'] != null
        ? DateFormat('dd.MM.yyyy').format(DateTime.parse(application['applied_at'] as String))
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getStatusIcon(status),
                  color: _getStatusColor(status),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectionTitle,
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _getStatusColor(status)),
                          ),
                          child: Text(
                            _getStatusText(status),
                            style: GoogleFonts.roboto(
                              fontSize: 11,
                              color: _getStatusColor(status),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          appliedDate,
                          style: GoogleFonts.roboto(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (status == 'pending')
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                  onPressed: () => _cancelApplication(application['id'] as String),
                  tooltip: 'Отменить заявку',
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Вспомогательные методы
  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      case 'cancelled':
        return Colors.grey;
      case 'waiting_list':
        return AppColors.info;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'rejected':
        return Icons.cancel;
      case 'cancelled':
        return Icons.cancel;
      case 'waiting_list':
        return Icons.hourglass_empty;
      default:
        return Icons.help;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'Принято';
      case 'pending':
        return 'На рассмотрении';
      case 'rejected':
        return 'Отклонено';
      case 'cancelled':
        return 'Отменено';
      case 'waiting_list':
        return 'Лист ожидания';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final filteredClubs = _getFilteredClubs();

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Загрузка фракций...', style: GoogleFonts.roboto()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                _errorMessage!,
                style: GoogleFonts.roboto(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadData,
                child: Text('Повторить попытку', style: GoogleFonts.roboto()),
              ),
            ],
          ),
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              expandedHeight: 320,
              collapsedHeight: 60,
              pinned: true,
              floating: false,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.05),
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  return FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    background: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: _buildHeader(),
                      ),
                    ),
                  );
                },
              ),
            ),

            SliverToBoxAdapter(
              child: _buildMyApplications(),
            ),

            if (filteredClubs.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.group_off,
                        size: 80,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Фракции по запросу не найдены'
                            : 'Фракции не найдены',
                        style: GoogleFonts.roboto(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_searchQuery.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: Text('Очистить поиск', style: GoogleFonts.roboto()),
                        ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildClubCard(filteredClubs[index]),
                  childCount: filteredClubs.length,
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 32),
            ),
          ],
        ),
      ),
      floatingActionButton: _isSubmitting
          ? FloatingActionButton(
        onPressed: null,
        backgroundColor: AppColors.primary,
        child: const CircularProgressIndicator(color: Colors.white),
      )
          : null,
    );
  }
}

// Модальное окно с деталями кружка
class _ClubDetailsModal extends StatelessWidget {
  final Map<String, dynamic> club;
  final List<Map<String, dynamic>> myApplications;
  final VoidCallback onApply;
  final bool isSubmitting;

  const _ClubDetailsModal({
    required this.club,
    required this.myApplications,
    required this.onApply,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    final coachName = club['coach_name'] ?? 'Не назначен';
    final currentMembers = club['current_members'] as int? ?? 0;
    final capacity = club['capacity'] as int? ?? 0;
    final isActive = club['is_active'] as bool? ?? true;
    final isRegistrationOpen = club['registration_open'] as bool? ?? true;

    final hasCapacity = capacity == 0 || currentMembers < capacity;
    final canApply = isActive && isRegistrationOpen && hasCapacity;

    final myApplication = myApplications.firstWhere(
          (app) => app['section_id'] == club['id'],
      orElse: () => <String, dynamic>{},
    );

    final hasApplied = myApplication.isNotEmpty;
    final status = myApplication['status'] as String? ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Хендл
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Заголовок
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.flag,
                        color: AppColors.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            club['title']?.toString() ?? 'Без названия',
                            style: GoogleFonts.roboto(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Руководитель: $coachName',
                            style: GoogleFonts.roboto(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Контент
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Статус
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Фракция',
                              style: GoogleFonts.roboto(
                                fontSize: 14,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Неактивно',
                                style: GoogleFonts.roboto(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Описание
                      if (club['description'] != null && (club['description'] as String).isNotEmpty) ...[
                        Text(
                          'Описание',
                          style: GoogleFonts.roboto(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          club['description'].toString(),
                          style: GoogleFonts.roboto(fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Детали
                      Text(
                        'Информация',
                        style: GoogleFonts.roboto(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _buildDetailRow(
                        context,
                        Icons.schedule,
                        'Расписание:',
                        club['schedule']?.toString() ?? 'Не указано',
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        context,
                        Icons.location_on,
                        'Место:',
                        [club['location'], club['room'], club['building']]
                            .where((e) => e != null && e.toString().isNotEmpty)
                            .join(', ') ?? 'Не указано',
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        context,
                        Icons.people,
                        'Участников:',
                        capacity > 0
                            ? '$currentMembers/$capacity (${capacity - currentMembers} свободно)'
                            : '$currentMembers участников',
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        context,
                        Icons.app_registration,
                        'Регистрация:',
                        isRegistrationOpen ? 'Открыта' : 'Закрыта',
                      ),

                      const SizedBox(height: 32),

                      // Состояние заявки
                      if (hasApplied)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _getStatusColor(status)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Статус вашей заявки',
                                style: GoogleFonts.roboto(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _getStatusIcon(status),
                                    color: _getStatusColor(status),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _getStatusText(status),
                                    style: GoogleFonts.roboto(
                                      fontSize: 24,
                                      color: _getStatusColor(status),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              if (myApplication['applied_at'] != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Дата подачи: ${DateFormat('dd.MM.yyyy').format(DateTime.parse(myApplication['applied_at'] as String))}',
                                  style: GoogleFonts.roboto(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      else if (canApply)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : onApply,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : Text(
                              'Подать заявку',
                              style: GoogleFonts.roboto(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.do_not_disturb,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  !isRegistrationOpen
                                      ? 'Регистрация закрыта'
                                      : 'Фракция заполнена',
                                  style: GoogleFonts.roboto(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  !isRegistrationOpen
                                      ? 'Набор участников временно приостановлен'
                                      : 'Нет свободных мест',
                                  style: GoogleFonts.roboto(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.roboto(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      case 'cancelled':
        return Colors.grey;
      case 'waiting_list':
        return AppColors.info;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'rejected':
        return Icons.cancel;
      case 'cancelled':
        return Icons.cancel;
      case 'waiting_list':
        return Icons.hourglass_empty;
      default:
        return Icons.help;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'Принято';
      case 'pending':
        return 'На рассмотрении';
      case 'rejected':
        return 'Отклонено';
      case 'cancelled':
        return 'Отменено';
      case 'waiting_list':
        return 'Лист ожидания';
      default:
        return status;
    }
  }
}