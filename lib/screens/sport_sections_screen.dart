import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart'; // Добавлен импорт Google Fonts
import '../core/theme.dart';

class SportSectionsScreen extends StatefulWidget {
  const SportSectionsScreen({super.key});

  @override
  State<SportSectionsScreen> createState() => _SportSectionsScreenState();
}

class _SportSectionsScreenState extends State<SportSectionsScreen>
    with AutomaticKeepAliveClientMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Состояние
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Данные
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _myApplications = [];
  Map<String, dynamic>? _selectedSection;

  // Фильтры
  String _selectedFilter = 'all';
  final List<String> _filters = ['all', 'available', 'my_sections'];

  // Поиск
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      final user = _supabase.auth.currentUser;
      if (user == null) {
        _redirectToLogin();
        return;
      }

      // Загружаем все спортивные секции
      final sectionsResponse = await _supabase
          .from('extended_sections')
          .select('''
          id, title, description, coach_name, schedule, 
          location, capacity, current_members, type, category, 
          is_active, registration_open, requirements, equipment_needed,
          coach_id
        ''')
          .eq('type', 'sport')
          .order('title');

      // ВАЖНО: Исправляем запрос подсчета - используем rpc или другой подход
      // Вместо неправильного синтаксиса используем отдельный запрос
      final allApprovedApps = await _supabase
          .from('section_applications')
          .select('section_id, status')
          .eq('status', 'approved');

      // Подсчитываем вручную
      final countsMap = <String, int>{};
      for (final app in allApprovedApps) {
        final sectionId = app['section_id'] as String?;
        if (sectionId != null) {
          countsMap[sectionId] = (countsMap[sectionId] ?? 0) + 1;
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

      // Получаем информацию о секциях для моих заявок
      final myApplicationsWithDetails = [];
      for (final app in applicationsResponse) {
        final sectionId = app['section_id'] as String?;
        if (sectionId != null) {
          final sectionInfo = await _supabase
              .from('extended_sections')
              .select('title, schedule, location, category')
              .eq('id', sectionId)
              .single()
              .catchError((e) => null);

          if (sectionInfo != null) {
            myApplicationsWithDetails.add({
              ...app,
              'sections': sectionInfo,
            });
          }
        }
      }

      // Объединяем данные
      final List<Map<String, dynamic>> sectionsWithCounts = [];
      for (final section in sectionsResponse) {
        final sectionId = section['id'] as String? ?? '';
        final count = countsMap[sectionId] ?? 0;

        sectionsWithCounts.add({
          ...section,
          'applications_count': count,
        });
      }

      setState(() {
        _sections = sectionsWithCounts;
        _myApplications = List<Map<String, dynamic>>.from(myApplicationsWithDetails);
      });
    } catch (error) {
      debugPrint('Error loading sections: $error');
      setState(() {
        _errorMessage = 'Не удалось загрузить секции: $error';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/login');
    });
  }

  Future<void> _applyForSection(Map<String, dynamic> section) async {
    try {
      setState(() => _isSubmitting = true);

      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Проверяем, не подал ли уже заявку
      final existingApplication = await _supabase
          .from('section_applications') // ИСПРАВЛЕНО: было 'sections_applications'
          .select('*')
          .eq('applicant_id', user.id) // ИСПРАВЛЕНО: было 'student_id'
          .eq('section_id', section['id'])
          .maybeSingle();

      if (existingApplication != null) {
        context.showSnackBar('Вы уже подали заявку на эту секцию');
        return;
      }

      // Проверяем, есть ли свободные места
      final currentMembers = section['current_members'] as int? ?? 0;
      final capacity = section['capacity'] as int? ?? 0;
      final isRegistrationOpen = section['registration_open'] as bool? ?? true;

      if (!isRegistrationOpen) {
        context.showSnackBar('Регистрация на эту секцию закрыта', isError: true);
        return;
      }

      if (capacity > 0 && currentMembers >= capacity) {
        context.showSnackBar('На эту секцию нет свободных мест', isError: true);
        return;
      }

      // Создаем заявку
      await _supabase.from('section_applications').insert({
        'applicant_id': user.id, // ИСПРАВЛЕНО: было 'student_id'
        'section_id': section['id'],
        'status': 'pending',
        'applied_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      context.showSnackBar('Заявка подана успешно!');

      // Обновляем данные
      await _loadData();
    } catch (error) {
      debugPrint('Error applying for section: $error');
      context.showSnackBar('Ошибка при подаче заявки: $error', isError: true);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _cancelApplication(String applicationId) async {
    try {
      await _supabase
          .from('section_applications') // ИСПРАВЛЕНО: было 'sections_applications'
          .update({
        'status': 'cancelled',
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', applicationId);

      context.showSnackBar('Заявка отменена');

      // Обновляем данные
      await _loadData();
    } catch (error) {
      debugPrint('Error canceling application: $error');
      context.showSnackBar('Ошибка при отмене заявки', isError: true);
    }
  }

  void _showSectionDetails(Map<String, dynamic> section) {
    setState(() => _selectedSection = section);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SectionDetailsModal(
        section: section,
        myApplications: _myApplications,
        onApply: () => _applyForSection(section),
        isSubmitting: _isSubmitting,
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredSections() {
    List<Map<String, dynamic>> sections = _sections;

    // Применяем поиск
    if (_searchQuery.isNotEmpty) {
      sections = sections.where((section) {
        return section['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            section['description'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            section['coach_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Применяем фильтры
    if (_selectedFilter == 'available') {
      sections = sections.where((section) {
        final currentMembers = section['current_members'] as int? ?? 0;
        final capacity = section['capacity'] as int? ?? 0;
        final isActive = section['is_active'] as bool? ?? true;
        final isRegistrationOpen = section['registration_open'] as bool? ?? true;

        return isActive &&
            isRegistrationOpen &&
            (capacity == 0 || currentMembers < capacity);
      }).toList();
    } else if (_selectedFilter == 'my_sections') {
      final mySectionIds = _myApplications
          .where((app) => app['status'] == 'approved')
          .map((app) => app['section_id'])
          .toList();

      sections = sections.where((section) => mySectionIds.contains(section['id'])).toList();
    }

    return sections;
  }

  Widget _buildHeader() {
    final approvedCount = _myApplications.where((app) => app['status'] == 'approved').length;
    final pendingCount = _myApplications.where((app) => app['status'] == 'pending').length;

    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Спортивные секции',
            style: GoogleFonts.roboto(
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),

          // Статистика
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Мои секции',
                  '$approvedCount',
                  Icons.sports_soccer,
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Заявки',
                  '$pendingCount',
                  Icons.pending_actions,
                  AppColors.warning,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Поиск
          TextField(
            controller: _searchController,
            style: GoogleFonts.roboto(),
            decoration: InputDecoration(
              hintText: 'Поиск секций...',
              hintStyle: GoogleFonts.roboto(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),

          const SizedBox(height: 16),

          // Фильтры
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text('Все', style: GoogleFonts.roboto()),
                  selected: _selectedFilter == 'all',
                  onSelected: (_) => setState(() => _selectedFilter = 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Доступные', style: GoogleFonts.roboto()),
                  selected: _selectedFilter == 'available',
                  onSelected: (_) => setState(() => _selectedFilter = 'available'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Мои', style: GoogleFonts.roboto()),
                  selected: _selectedFilter == 'my_sections',
                  onSelected: (_) => setState(() => _selectedFilter = 'my_sections'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.roboto(
                  fontSize: 24,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                title,
                style: GoogleFonts.roboto(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(Map<String, dynamic> section) {
    final coachName = section['coach_name'] ?? 'Не назначен';
    final currentMembers = section['current_members'] as int? ?? 0;
    final capacity = section['capacity'] as int? ?? 0;
    final isActive = section['is_active'] as bool? ?? true;
    final isRegistrationOpen = section['registration_open'] as bool? ?? true;

    final hasCapacity = capacity == 0 || currentMembers < capacity;
    final canApply = isActive && isRegistrationOpen && hasCapacity;

    final myApplication = _myApplications.firstWhere(
          (app) => app['section_id'] == section['id'],
      orElse: () => <String, dynamic>{},
    );

    return ModernCard(
      onTap: () => _showSectionDetails(section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getSectionIcon(section['category']),
                  color: AppColors.primary,
                  size: 24,
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
                            section['title'],
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
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Тренер: $coachName',
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (myApplication.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(myApplication['status']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getStatusColor(myApplication['status'])),
                  ),
                  child: Text(
                    _getStatusText(myApplication['status']),
                    style: GoogleFonts.roboto(
                      fontSize: 11,
                      color: _getStatusColor(myApplication['status']),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          if (section['description'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                section['description'],
                style: GoogleFonts.roboto(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${section['schedule']}',
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.people,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 4),
              Text(
                capacity > 0
                    ? '$currentMembers/$capacity'
                    : '$currentMembers мест',
                style: GoogleFonts.roboto(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (myApplication.isEmpty && canApply)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _applyForSection(section),
                child: Text('Подать заявку', style: GoogleFonts.roboto()),
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
    );
  }

  Widget _buildMyApplications() {
    if (_myApplications.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Мои заявки',
            style: GoogleFonts.roboto(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ..._myApplications.map((application) {
          final section = application['sections'] ?? {};
          final sectionTitle = section['title'] ?? 'Неизвестная секция';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ModernCard(
              child: Row(
                children: [
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
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusColor(application['status']).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _getStatusColor(application['status'])),
                              ),
                              child: Text(
                                _getStatusText(application['status']),
                                style: GoogleFonts.roboto(
                                  fontSize: 11,
                                  color: _getStatusColor(application['status']),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (application['applied_at'] != null)
                              Text(
                                DateFormat('dd.MM.yyyy').format(
                                  DateTime.parse(application['applied_at']),
                                ),
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
                  if (application['status'] == 'pending')
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _cancelApplication(application['id']),
                      tooltip: 'Отменить заявку',
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  IconData _getSectionIcon(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'football':
        return Icons.sports_soccer;
      case 'basketball':
        return Icons.sports_basketball;
      case 'volleyball':
        return Icons.sports_volleyball;
      case 'tennis':
        return Icons.sports_tennis;
      case 'swimming':
        return Icons.pool;
      case 'gym':
      case 'fitness':
        return Icons.fitness_center;
      case 'chess':
        return Icons.casino;
      case 'dance':
        return Icons.music_note;
      default:
        return Icons.sports;
    }
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

    final filteredSections = _getFilteredSections();

    return Scaffold(
      appBar: AppBar(
        title: Text('Спортивные секции', style: GoogleFonts.roboto()),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.roboto(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              child: Text('Повторить', style: GoogleFonts.roboto()),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildHeader(),
              ),
              const SizedBox(height: 16),
              _buildMyApplications(),
              const SizedBox(height: 16),
              if (filteredSections.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.sports_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Секции по запросу не найдены'
                            : 'Секции не найдены',
                        style: GoogleFonts.roboto(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...filteredSections.map((section) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: _buildSectionCard(section),
                  );
                }).toList(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// Модальное окно с деталями секции
class _SectionDetailsModal extends StatelessWidget {
  final Map<String, dynamic> section;
  final List<Map<String, dynamic>> myApplications;
  final VoidCallback onApply;
  final bool isSubmitting;

  const _SectionDetailsModal({
    required this.section,
    required this.myApplications,
    required this.onApply,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    final coachName = section['coach_name'] ?? 'Не назначен';
    final currentMembers = section['current_members'] as int? ?? 0;
    final capacity = section['capacity'] as int? ?? 0;
    final isActive = section['is_active'] as bool? ?? true;
    final isRegistrationOpen = section['registration_open'] as bool? ?? true;

    final hasCapacity = capacity == 0 || currentMembers < capacity;
    final canApply = isActive && isRegistrationOpen && hasCapacity;

    final myApplication = myApplications.firstWhere(
          (app) => app['section_id'] == section['id'],
      orElse: () => <String, dynamic>{},
    );
    final hasApplied = myApplication.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
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
          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _getSectionIcon(section['category']),
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
                            section['title'],
                            style: GoogleFonts.roboto(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Тренер: $coachName',
                            style: GoogleFonts.roboto(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Неактивно',
                          style: GoogleFonts.roboto(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                if (section['description'] != null && section['description'].toString().isNotEmpty) ...[
                  Text(
                    section['description'].toString(),
                    style: GoogleFonts.roboto(fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                ],

                // Информация
                ModernCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        context,
                        'Расписание:',
                        section['schedule'] ?? 'Не указано',
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        context,
                        'Место проведения:',
                        section['location'] ?? 'Не указано',
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        context,
                        'Мест:',
                        capacity > 0
                            ? '$currentMembers/$capacity (${capacity - currentMembers} свободно)'
                            : '$currentMembers мест',
                      ),
                      const SizedBox(height: 12),
                      if (section['category'] != null)
                        _buildDetailRow(
                          context,
                          'Категория:',
                          _getCategoryName(section['category']),
                        ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        context,
                        'Регистрация:',
                        isRegistrationOpen ? 'Открыта' : 'Закрыта',
                      ),
                    ],
                  ),
                ),

                // Требования и оборудование
                if ((section['requirements'] as List?)?.isNotEmpty == true ||
                    (section['equipment_needed'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Требования и оборудование:',
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ModernCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((section['requirements'] as List?)?.isNotEmpty == true) ...[
                          Text(
                            'Требования:',
                            style: GoogleFonts.roboto(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...(section['requirements'] as List).map((req) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 4),
                              child: Text(
                                '• $req',
                                style: GoogleFonts.roboto(fontSize: 14),
                              ),
                            );
                          }).toList(),
                        ],
                        if ((section['equipment_needed'] as List?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Необходимое оборудование:',
                            style: GoogleFonts.roboto(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...(section['equipment_needed'] as List).map((eq) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 4),
                              child: Text(
                                '• $eq',
                                style: GoogleFonts.roboto(fontSize: 14),
                              ),
                            );
                          }).toList(),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Кнопки действий
                if (hasApplied)
                  ModernCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Статус заявки:',
                          style: GoogleFonts.roboto(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _getStatusColor(myApplication['status']).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _getStatusColor(myApplication['status']),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _getStatusText(myApplication['status']),
                                style: GoogleFonts.roboto(
                                  fontSize: 16,
                                  color: _getStatusColor(myApplication['status']),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (myApplication['status'] == 'pending')
                                const SizedBox(width: 8),
                              if (myApplication['status'] == 'pending')
                                const Icon(
                                  Icons.pending,
                                  size: 20,
                                  color: AppColors.warning,
                                ),
                            ],
                          ),
                        ),
                        if (myApplication['motivation'] != null && myApplication['motivation'].toString().isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Ваша мотивация:',
                            style: GoogleFonts.roboto(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            myApplication['motivation'].toString(),
                            style: GoogleFonts.roboto(fontSize: 14),
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Text('Подать заявку', style: GoogleFonts.roboto()),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        !isRegistrationOpen
                            ? 'Регистрация на эту секцию закрыта'
                            : 'На эту секцию нет свободных мест',
                        style: GoogleFonts.roboto(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: GoogleFonts.roboto(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.roboto(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  IconData _getSectionIcon(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'football':
        return Icons.sports_soccer;
      case 'basketball':
        return Icons.sports_basketball;
      case 'volleyball':
        return Icons.sports_volleyball;
      case 'tennis':
        return Icons.sports_tennis;
      case 'swimming':
        return Icons.pool;
      case 'gym':
      case 'fitness':
        return Icons.fitness_center;
      case 'chess':
        return Icons.casino;
      case 'dance':
        return Icons.music_note;
      default:
        return Icons.sports;
    }
  }

  String _getCategoryName(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'football':
        return 'Футбол';
      case 'basketball':
        return 'Баскетбол';
      case 'volleyball':
        return 'Волейбол';
      case 'tennis':
        return 'Теннис';
      case 'swimming':
        return 'Плавание';
      case 'gym':
      case 'fitness':
        return 'Фитнес';
      case 'chess':
        return 'Шахматы';
      case 'dance':
        return 'Танцы';
      default:
        return category ?? 'Другое';
    }
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