import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';

class CirclesScreen extends StatefulWidget {
  const CirclesScreen({super.key});

  @override
  State<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends State<CirclesScreen>
    with AutomaticKeepAliveClientMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Состояние
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Данные
  List<Map<String, dynamic>> _circles = [];
  List<Map<String, dynamic>> _myApplications = [];
  Map<String, dynamic>? _selectedCircle;

  // Фильтры
  String _selectedFilter = 'all';
  final List<String> _filters = ['all', 'available', 'my_circles'];

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

      // Загружаем все кружки
      final circlesResponse = await _supabase
          .from('extended_sections')
          .select('''
          id, title, description, coach_name, schedule, 
          location, capacity, current_members, type, category, 
          is_active, registration_open, requirements, equipment_needed,
          coach_id, teacher_supervisor, room, building
        ''')
          .eq('type', 'circle')
          .order('title');

      // Подсчитываем количество участников
      final allApprovedApps = await _supabase
          .from('section_applications')
          .select('section_id, status')
          .eq('status', 'approved');

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

      // Получаем информацию о кружках для моих заявок
      final myApplicationsWithDetails = [];
      for (final app in applicationsResponse) {
        final sectionId = app['section_id'] as String?;
        if (sectionId != null) {
          final circleInfo = await _supabase
              .from('extended_sections')
              .select('title, schedule, location, category, type')
              .eq('id', sectionId)
              .single()
              .catchError((e) => null);

          if (circleInfo != null && circleInfo['type'] == 'circle') {
            myApplicationsWithDetails.add({
              ...app,
              'circle_details': circleInfo,
            });
          }
        }
      }

      // Объединяем данные
      final List<Map<String, dynamic>> circlesWithCounts = [];
      for (final circle in circlesResponse) {
        final circleId = circle['id'] as String? ?? '';
        final count = countsMap[circleId] ?? 0;

        circlesWithCounts.add({
          ...circle,
          'applications_count': count,
        });
      }

      setState(() {
        _circles = circlesWithCounts;
        _myApplications = List<Map<String, dynamic>>.from(myApplicationsWithDetails);
      });
    } catch (error) {
      debugPrint('Error loading circles: $error');
      setState(() {
        _errorMessage = 'Не удалось загрузить кружки: $error';
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

  Future<void> _applyForCircle(Map<String, dynamic> circle) async {
    try {
      setState(() => _isSubmitting = true);

      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Проверяем, не подал ли уже заявку
      final existingApplication = await _supabase
          .from('section_applications')
          .select('*')
          .eq('applicant_id', user.id)
          .eq('section_id', circle['id'])
          .maybeSingle();

      if (existingApplication != null) {
        _showSnackBar('Вы уже подали заявку на этот кружок');
        return;
      }

      // Проверяем, есть ли свободные места
      final currentMembers = circle['current_members'] as int? ?? 0;
      final capacity = circle['capacity'] as int? ?? 0;
      final isRegistrationOpen = circle['registration_open'] as bool? ?? true;

      if (!isRegistrationOpen) {
        _showSnackBar('Регистрация на этот кружок закрыта', isError: true);
        return;
      }

      if (capacity > 0 && currentMembers >= capacity) {
        _showSnackBar('На этот кружок нет свободных мест', isError: true);
        return;
      }

      // Создаем заявку
      await _supabase.from('section_applications').insert({
        'applicant_id': user.id,
        'section_id': circle['id'],
        'status': 'pending',
        'applied_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      _showSnackBar('Заявка подана успешно!');

      // Обновляем данные
      await _loadData();
    } catch (error) {
      debugPrint('Error applying for circle: $error');
      _showSnackBar('Ошибка при подаче заявки: $error', isError: true);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _cancelApplication(String applicationId) async {
    try {
      await _supabase
          .from('section_applications')
          .update({
        'status': 'cancelled',
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', applicationId);

      _showSnackBar('Заявка отменена');

      // Обновляем данные
      await _loadData();
    } catch (error) {
      debugPrint('Error canceling application: $error');
      _showSnackBar('Ошибка при отмене заявки', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _showCircleDetails(Map<String, dynamic> circle) {
    setState(() => _selectedCircle = circle);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CircleDetailsModal(
        circle: circle,
        myApplications: _myApplications,
        onApply: () => _applyForCircle(circle),
        isSubmitting: _isSubmitting,
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredCircles() {
    List<Map<String, dynamic>> circles = _circles;

    // Применяем поиск
    if (_searchQuery.isNotEmpty) {
      circles = circles.where((circle) {
        return circle['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            circle['description'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            circle['coach_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            circle['category'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Применяем фильтры
    if (_selectedFilter == 'available') {
      circles = circles.where((circle) {
        final currentMembers = circle['current_members'] as int? ?? 0;
        final capacity = circle['capacity'] as int? ?? 0;
        final isActive = circle['is_active'] as bool? ?? true;
        final isRegistrationOpen = circle['registration_open'] as bool? ?? true;

        return isActive &&
            isRegistrationOpen &&
            (capacity == 0 || currentMembers < capacity);
      }).toList();
    } else if (_selectedFilter == 'my_circles') {
      final myCircleIds = _myApplications
          .where((app) => app['status'] == 'approved')
          .map((app) => app['section_id'])
          .toList();

      circles = circles.where((circle) => myCircleIds.contains(circle['id'])).toList();
    }

    // Сортируем по категориям для лучшего отображения
    circles.sort((a, b) {
      final catA = a['category'] ?? '';
      final catB = b['category'] ?? '';
      return catA.compareTo(catB);
    });

    return circles;
  }

  Widget _buildHeader() {
    final approvedCount = _myApplications.where((app) => app['status'] == 'approved').length;
    final pendingCount = _myApplications.where((app) => app['status'] == 'pending').length;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Кружки колледжа',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Творческие и образовательные кружки для развития талантов',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 16),

            // Статистика
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Мои кружки',
                    '$approvedCount',
                    Icons.group,
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
              style: TextStyle(fontFamily: 'Roboto'),
              decoration: InputDecoration(
                hintText: 'Поиск кружков...',
                hintStyle: TextStyle(fontFamily: 'Roboto'),
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
                    label: Text('Все', style: TextStyle(fontFamily: 'Roboto')),
                    selected: _selectedFilter == 'all',
                    onSelected: (_) => setState(() => _selectedFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('Доступные', style: TextStyle(fontFamily: 'Roboto')),
                    selected: _selectedFilter == 'available',
                    onSelected: (_) => setState(() => _selectedFilter = 'available'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('Мои кружки', style: TextStyle(fontFamily: 'Roboto')),
                    selected: _selectedFilter == 'my_circles',
                    onSelected: (_) => setState(() => _selectedFilter = 'my_circles'),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                style: TextStyle(
                  fontSize: 24,
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircleCard(Map<String, dynamic> circle) {
    final coachName = circle['coach_name'] ?? 'Не назначен';
    final currentMembers = circle['current_members'] as int? ?? 0;
    final capacity = circle['capacity'] as int? ?? 0;
    final isActive = circle['is_active'] as bool? ?? true;
    final isRegistrationOpen = circle['registration_open'] as bool? ?? true;

    final hasCapacity = capacity == 0 || currentMembers < capacity;
    final canApply = isActive && isRegistrationOpen && hasCapacity;

    final myApplication = _myApplications.firstWhere(
          (app) => app['section_id'] == circle['id'],
      orElse: () => <String, dynamic>{},
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _showCircleDetails(circle),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                      color: _getCategoryColor(circle['category']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getCircleIcon(circle['category']),
                      color: _getCategoryColor(circle['category']),
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
                                circle['title'],
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Roboto',
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getCategoryColor(circle['category']).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getCategoryName(circle['category']),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _getCategoryColor(circle['category']),
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Руководитель: $coachName',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  fontFamily: 'Roboto',
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ],
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
                        style: TextStyle(
                          fontSize: 11,
                          color: _getStatusColor(myApplication['status']),
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              if (circle['description'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    circle['description'],
                    style: TextStyle(fontSize: 14, fontFamily: 'Roboto'),
                    maxLines: 2,
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
                      '${circle['schedule']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        fontFamily: 'Roboto',
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    circle['location'] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      fontFamily: 'Roboto',
                    ),
                    maxLines: 1,
                  ),
                ],
              ),

              const SizedBox(height: 8),

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
                        ? '$currentMembers/$capacity участников'
                        : '$currentMembers участников',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (myApplication.isEmpty && canApply)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _applyForCircle(circle),
                    child: Text('Записаться', style: TextStyle(fontFamily: 'Roboto')),
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
                      'Запись закрыта',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontFamily: 'Roboto',
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
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontFamily: 'Roboto',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Мои заявки',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto',
            ),
          ),
        ),
        ..._myApplications.map((application) {
          final circle = application['circle_details'] ?? {};
          final circleTitle = circle['title'] ?? 'Неизвестный кружок';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getCategoryColor(circle['category']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getCircleIcon(circle['category']),
                        color: _getCategoryColor(circle['category']),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            circleTitle,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Roboto',
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getStatusColor(application['status']),
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (application['applied_at'] != null)
                                Text(
                                  DateFormat('dd.MM.yyyy').format(
                                    DateTime.parse(application['applied_at']),
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    fontFamily: 'Roboto',
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
            ),
          );
        }).toList(),
      ],
    );
  }

  IconData _getCircleIcon(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'music':
        return Icons.music_note;
      case 'singing':
        return Icons.mic;
      case 'dance':
        return Icons.accessibility;
      case 'art':
        return Icons.palette;
      case 'theater':
        return Icons.theater_comedy;
      case 'literature':
        return Icons.menu_book;
      case 'education':
        return Icons.school;
      case 'craft':
        return Icons.build;
      case 'photography':
        return Icons.camera_alt;
      case 'technology':
        return Icons.computer;
      default:
        return Icons.group;
    }
  }

  Color _getCategoryColor(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'music':
        return const Color(0xFF4CAF50); // Зеленый
      case 'singing':
        return const Color(0xFF2196F3); // Синий
      case 'dance':
        return const Color(0xFFE91E63); // Розовый
      case 'art':
        return const Color(0xFFFF9800); // Оранжевый
      case 'education':
        return const Color(0xFF9C27B0); // Фиолетовый
      default:
        return AppColors.primary;
    }
  }

  String _getCategoryName(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'music':
        return 'Музыка';
      case 'singing':
        return 'Пение';
      case 'dance':
        return 'Танцы';
      case 'art':
        return 'Искусство';
      case 'theater':
        return 'Театр';
      case 'literature':
        return 'Литература';
      case 'education':
        return 'Образование';
      case 'craft':
        return 'Рукоделие';
      case 'photography':
        return 'Фотография';
      case 'technology':
        return 'Технологии';
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final filteredCircles = _getFilteredCircles();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Кружки'),
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
                style: TextStyle(fontSize: 14, fontFamily: 'Roboto'),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Повторить'),
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
              if (filteredCircles.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.group_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Кружки по запросу не найдены'
                            : 'Кружки не найдены',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          fontFamily: 'Roboto',
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        const SizedBox(height: 8),
                      if (_searchQuery.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Text('Очистить поиск'),
                        ),
                    ],
                  ),
                )
              else
                ...filteredCircles.map((circle) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: _buildCircleCard(circle),
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

// Модальное окно с деталями кружка
class _CircleDetailsModal extends StatelessWidget {
  final Map<String, dynamic> circle;
  final List<Map<String, dynamic>> myApplications;
  final VoidCallback onApply;
  final bool isSubmitting;

  const _CircleDetailsModal({
    required this.circle,
    required this.myApplications,
    required this.onApply,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    final coachName = circle['coach_name'] ?? 'Не назначен';
    final currentMembers = circle['current_members'] as int? ?? 0;
    final capacity = circle['capacity'] as int? ?? 0;
    final isActive = circle['is_active'] as bool? ?? true;
    final isRegistrationOpen = circle['registration_open'] as bool? ?? true;

    final hasCapacity = capacity == 0 || currentMembers < capacity;
    final canApply = isActive && isRegistrationOpen && hasCapacity;

    final myApplication = myApplications.firstWhere(
          (app) => app['section_id'] == circle['id'],
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
                        color: _getCategoryColor(circle['category']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _getCircleIcon(circle['category']),
                        color: _getCategoryColor(circle['category']),
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            circle['title'],
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Roboto',
                            ),
                          ),
                          Text(
                            'Руководитель: $coachName',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              fontFamily: 'Roboto',
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
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                if (circle['description'] != null && circle['description'].toString().isNotEmpty) ...[
                  Text(
                    circle['description'].toString(),
                    style: TextStyle(fontSize: 14, fontFamily: 'Roboto'),
                  ),
                  const SizedBox(height: 24),
                ],

                // Информация
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          context,
                          'Расписание:',
                          circle['schedule'] ?? 'Не указано',
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          context,
                          'Место проведения:',
                          circle['location'] ?? 'Не указано',
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
                        _buildDetailRow(
                          context,
                          'Категория:',
                          _getCategoryName(circle['category']),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          context,
                          'Запись:',
                          isRegistrationOpen ? 'Открыта' : 'Закрыта',
                        ),
                      ],
                    ),
                  ),
                ),

                // Требования и оборудование
                if ((circle['requirements'] as List?)?.isNotEmpty == true ||
                    (circle['equipment_needed'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Требования и оборудование:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((circle['requirements'] as List?)?.isNotEmpty == true) ...[
                            Text(
                              'Требования:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...(circle['requirements'] as List).map((req) {
                              return Padding(
                                padding: const EdgeInsets.only(left: 8, bottom: 4),
                                child: Text(
                                  '• $req',
                                  style: TextStyle(fontSize: 14, fontFamily: 'Roboto'),
                                ),
                              );
                            }).toList(),
                          ],
                          if ((circle['equipment_needed'] as List?)?.isNotEmpty == true) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Необходимое оборудование:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...(circle['equipment_needed'] as List).map((eq) {
                              return Padding(
                                padding: const EdgeInsets.only(left: 8, bottom: 4),
                                child: Text(
                                  '• $eq',
                                  style: TextStyle(fontSize: 14, fontFamily: 'Roboto'),
                                ),
                              );
                            }).toList(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Кнопки действий
                if (hasApplied)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            'Статус заявки:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Roboto',
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
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _getStatusColor(myApplication['status']),
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Roboto',
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
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              myApplication['motivation'].toString(),
                              style: TextStyle(fontSize: 14, fontFamily: 'Roboto'),
                            ),
                          ],
                        ],
                      ),
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
                          : const Text('Записаться на кружок'),
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
                            ? 'Запись на этот кружок закрыта'
                            : 'На этот кружок нет свободных мест',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontFamily: 'Roboto',
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
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500,
              fontFamily: 'Roboto',
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'Roboto',
            ),
          ),
        ),
      ],
    );
  }

  IconData _getCircleIcon(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'music':
        return Icons.music_note;
      case 'singing':
        return Icons.mic;
      case 'dance':
        return Icons.accessibility;
      case 'art':
        return Icons.palette;
      case 'education':
        return Icons.school;
      default:
        return Icons.group;
    }
  }

  Color _getCategoryColor(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'music':
        return const Color(0xFF4CAF50);
      case 'singing':
        return const Color(0xFF2196F3);
      case 'dance':
        return const Color(0xFFE91E63);
      case 'art':
        return const Color(0xFFFF9800);
      case 'education':
        return const Color(0xFF9C27B0);
      default:
        return AppColors.primary;
    }
  }

  String _getCategoryName(String? category) {
    final cat = (category ?? '').toLowerCase();

    switch (cat) {
      case 'music':
        return 'Музыка';
      case 'singing':
        return 'Пение';
      case 'dance':
        return 'Танцы';
      case 'art':
        return 'Искусство';
      case 'education':
        return 'Образование';
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