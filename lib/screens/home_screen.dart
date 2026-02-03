import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import 'coupons_screen.dart';
import 'sport_sections_screen.dart';
import 'clubs_screen.dart';
import 'circles_screen.dart'; // Добавлен импорт CirclesScreen
import 'food_preorder_screen.dart';
import 'admin_dashboard_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic>? initialProfile;

  const HomeScreen({super.key, this.initialProfile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex = 0;
  late List<Widget> _pages;
  late List<String> _pageTitles;

  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _sessionTimer;
  bool _hasInternetConnection = true;
  DateTime? _lastProfileUpdate;

  late AnimationController _refreshAnimationController;
  late Animation<double> _refreshAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _refreshAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);

    _refreshAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _refreshAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Инициализируем профиль из initialProfile, если он передан
    if (widget.initialProfile != null) {
      _userProfile = widget.initialProfile;
      _isLoading = false;
    }

    _initializePages();
    _loadUserData();
    _startSessionTimer();
    _checkInternetConnection();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _resumeApp();
        break;
      case AppLifecycleState.paused:
        _pauseApp();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _initializePages() {
    _pages = [
      _HomeTab(
        onRefresh: _refreshHomeData,
        onFoodOrderPressed: _onFoodOrderPressed,
      ),
      const CirclesScreen(), // Заменен ScheduleScreen на CirclesScreen
      const CouponsScreen(),
      const SportSectionsScreen(),
      const ClubsScreen(),
    ];

    _pageTitles = [
      'Главная',
      'Кружки', // Изменено с 'Расписание' на 'Кружки'
      'Талоны',
      'Спорт-секции',
      'Жигер',
    ];
  }

  Future<void> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      setState(() {
        _hasInternetConnection = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      });
    } on SocketException catch (_) {
      setState(() => _hasInternetConnection = false);
    }
  }

  void _startSessionTimer() {
    _sessionTimer = Timer.periodic(
      const Duration(minutes: 5),
          (_) => _refreshSession(),
    );
  }

  Future<void> _refreshSession() async {
    try {
      // Проверяем, что пользователь еще авторизован
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Обновляем last_seen в профиле
      await _supabase.from('profiles').update({
        'last_seen': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
    } catch (e) {
      debugPrint('Ошибка обновления сессии: $e');
    }
  }

  Future<void> _loadUserData() async {
    if (!_hasInternetConnection) {
      setState(() {
        _errorMessage = 'Нет подключения к интернету. Проверьте соединение.';
        _isLoading = false;
      });
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _redirectToLogin();
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Используем кэширование - если данные обновлялись менее 5 минут назад, используем старые
      final now = DateTime.now();
      if (_lastProfileUpdate != null &&
          now.difference(_lastProfileUpdate!) < const Duration(minutes: 5) &&
          _userProfile != null) {
        setState(() => _isLoading = false);
        return;
      }

      try {
        // Пробуем получить профиль
        final response = await _supabase
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .single()
            .timeout(const Duration(seconds: 10));

        if (response != null) {
          _userProfile = Map<String, dynamic>.from(response);
        }
      } catch (e) {
        debugPrint('Ошибка загрузки профиля: $e');
        // Создаем минимальный профиль
        _userProfile = {
          'id': user.id,
          'email': user.email,
          'full_name': user.userMetadata?['full_name'] ?? user.email?.split('@').first ?? 'Пользователь',
          'role': 'student',
          'created_at': DateTime.now().toIso8601String(),
        };

        try {
          await _supabase.from('profiles').upsert(_userProfile!);
        } catch (error, stack) {
          debugPrint('Ошибка создания/обновления профиля: $error\n$stack');
        }
      }

      _lastProfileUpdate = DateTime.now();
      setState(() => _isLoading = false);
    } on TimeoutException {
      _handleTimeoutError();
    } on PostgrestException catch (e) {
      _handleDatabaseError(e);
    } catch (error) {
      _handleGeneralError(error);
    }
  }

  Future<void> _refreshHomeData() async {
    await _loadUserData();
  }

  void _handleTimeoutError() {
    setState(() {
      _errorMessage = 'Сервер не отвечает. Проверьте подключение.';
      _isLoading = false;
    });
  }

  void _handleDatabaseError(PostgrestException e) {
    debugPrint('Database error: ${e.message}');

    String errorMessage;
    switch (e.code) {
      case 'PGRST116':
        errorMessage = 'Ошибка конфигурации базы данных';
        break;
      case '42P01':
        errorMessage = 'Ошибка структуры базы данных';
        break;
      default:
        errorMessage = 'Ошибка сервера: ${e.message}';
    }

    setState(() {
      _errorMessage = errorMessage;
      _isLoading = false;
    });
  }

  void _handleGeneralError(dynamic error) {
    debugPrint('General error: $error');
    setState(() {
      _errorMessage = 'Не удалось загрузить данные. Попробуйте позже.';
      _isLoading = false;
    });
  }

  void _resumeApp() {
    _checkInternetConnection();
    if (_hasInternetConnection) {
      _loadUserData();
    }
  }

  void _pauseApp() {
    _refreshAnimationController.stop();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      _sessionTimer?.cancel();
      await _supabase.auth.signOut();

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при выходе: ${error.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    });
  }

  Future<bool> _onWillPop() {
    final now = DateTime.now();

    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return Future.value(false);
    }

    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нажмите еще раз для выхода')),
      );
      return Future.value(false);
    }

    return Future.value(true);
  }

  DateTime? _lastBackPress;

  void _onFoodOrderPressed() {
    if (!_hasInternetConnection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет подключения к интернету'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FoodPreorderScreen(),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Заголовок профиля
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.9),
                    AppColors.primary,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: _buildAvatarContent(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _userProfile?['full_name'] ?? 'Загрузка...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _userProfile?['email'] ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getRoleLabel(_userProfile?['role'] ?? 'student'),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_userProfile?['student_group'] != null)
                    _buildGroupInfo(),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: _buildDrawerItems(),
              ),
            ),

            _buildDrawerFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarContent() {
    final name = _userProfile?['full_name'] ?? '';
    final avatarUrl = _userProfile?['avatar_url'];

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Text(
              _getInitials(name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            );
          },
        ),
      );
    }

    return Text(
      _getInitials(name),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildGroupInfo() {
    final group = _userProfile?['student_group'];
    final speciality = _userProfile?['student_speciality'];

    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.school, size: 16, color: Colors.white.withOpacity(0.8)),
            const SizedBox(width: 6),
            Text(
              'Группа: $group',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
        if (speciality != null && speciality.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.work, size: 16, color: Colors.white.withOpacity(0.8)),
                const SizedBox(width: 6),
                Text(
                  'Специальность: $speciality',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildDrawerItems() {
    return [
      _buildDrawerTile(
        icon: Icons.person_outline,
        title: 'Мой профиль',
        subtitle: 'Просмотр и редактирование профиля',
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const ProfileScreen(),
            ),
          );
        },
      ),
      _buildDrawerTile(
        icon: Icons.restaurant_outlined,
        title: 'Предзаказ еды',
        subtitle: 'Выбрать обед на завтра',
        onTap: () {
          Navigator.of(context).pop();
          _onFoodOrderPressed();
        },
      ),
      _buildDrawerTile(
        icon: Icons.confirmation_number_outlined,
        title: 'Мои талоны',
        onTap: () {
          Navigator.of(context).pop();
          setState(() => _selectedIndex = 2);
        },
      ),
      _buildDrawerTile(
        icon: Icons.sports_outlined,
        title: 'Спортивные секции',
        onTap: () {
          Navigator.of(context).pop();
          setState(() => _selectedIndex = 3);
        },
      ),
      _buildDrawerTile(
        icon: Icons.groups_outlined,
        title: 'Кружки',
        onTap: () {
          Navigator.of(context).pop();
          setState(() => _selectedIndex = 1); // Изменено с 4 на 1
        },
      ),
      _buildDrawerTile(
        icon: Icons.groups_outlined,
        title: 'Жигер (Клубы)',
        onTap: () {
          Navigator.of(context).pop();
          setState(() => _selectedIndex = 4);
        },
      ),
      const Divider(),
      _buildDrawerTile(
        icon: Icons.settings_outlined,
        title: 'Настройки',
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const SettingsScreen(),
            ),
          );
        },
      ),
      if (_userProfile?['role'] == 'admin')
        _buildDrawerTile(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Админ-панель',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const AdminDashboardScreen(),
              ),
            );
          },
        ),
      _buildDrawerTile(
        icon: Icons.help_outline,
        title: 'Помощь',
        onTap: () {
          Navigator.of(context).pop();
          _showHelpDialog();
        },
      ),
      _buildDrawerTile(
        icon: Icons.logout_outlined,
        title: 'Выйти',
        color: AppColors.error,
        onTap: _logout,
      ),
    ];
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      onTap: onTap,
    );
  }

  Widget _buildDrawerFooter() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            'BOLASHAQ Колледж',
            style: AppTypography.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Версия 2.0.0 • © ${DateTime.now().year}',
            style: AppTypography.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Помощь'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Добро пожаловать в BOLASHAQ!',
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text('Приложение для студентов колледжа с функциями:'),
              const SizedBox(height: 8),
              _buildHelpItem('🏠 Главная - Расписание и новости'),
              _buildHelpItem('🎭 Кружки - Творческие и образовательные кружки'),
              _buildHelpItem('🎫 Талоны на питание'),
              _buildHelpItem('🥗 Предзаказ еды'),
              _buildHelpItem('⚽ Спортивные секции'),
              _buildHelpItem('🎯 Жигер - Студенческие клубы'),
              const SizedBox(height: 12),
              Text(
                'При возникновении проблем обращайтесь в деканат.',
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(
            child: Text(text, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (name.isNotEmpty) {
      return name.substring(0, 1).toUpperCase();
    }
    return '?';
  }

  String _getRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Администратор';
      case 'seller':
      case 'cashier':
        return 'Продавец';
      case 'teacher':
        return 'Преподаватель';
      case 'student':
        return 'Студент';
      case 'staff':
        return 'Персонал';
      default:
        return role;
    }
  }

  Widget _buildFloatingActionButton() {
    final role = _userProfile?['role'] ?? 'student';
    final hasFoodAccess = _userProfile?['verified_for_food'] ?? true;

    if (role == 'student' && hasFoodAccess) {
      return Container(
        margin: const EdgeInsets.only(bottom: 70),
        child: FloatingActionButton.extended(
          onPressed: _onFoodOrderPressed,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.restaurant_outlined),
          label: const Text('Заказать обед'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          elevation: 8,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildInternetConnectionIndicator() {
    if (_hasInternetConnection) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.orange,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            'Нет подключения к интернету',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = _userProfile?['role'] ?? 'student';

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildDrawer(),
        appBar: AppBar(
          title: const Text(
            'BOLASHAQ',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          actions: [
            if (!_hasInternetConnection)
              IconButton(
                icon: const Icon(Icons.wifi_off),
                color: Colors.orange,
                onPressed: _checkInternetConnection,
                tooltip: 'Нет подключения',
              ),
            if (_isLoading)
              FadeTransition(
                opacity: _refreshAnimation,
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (role == 'admin')
              IconButton(
                icon: const Icon(Icons.admin_panel_settings),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AdminDashboardScreen(),
                    ),
                  );
                },
                tooltip: 'Админ-панель',
              ),
          ],
        ),
        body: Column(
          children: [
            _buildInternetConnectionIndicator(),
            Expanded(
              child: _buildMainContent(),
            ),
          ],
        ),
        floatingActionButton: _buildFloatingActionButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null && _userProfile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.error,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _errorMessage!,
                style: AppTypography.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _loadUserData,
                    child: const Text('Повторить'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _logout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    child: const Text('Выйти'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return IndexedStack(
      index: _selectedIndex,
      children: _pages,
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Colors.grey,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Главная',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.groups), // Изменена иконка
          label: 'Кружки', // Изменена подпись
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.confirmation_number),
          label: 'Талоны',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.sports),
          label: 'Спорт-секции',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people),
          label: 'Жигер',
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _refreshAnimationController.dispose();
    super.dispose();
  }
}

// Вкладка "Главная"
class _HomeTab extends StatefulWidget {
  final VoidCallback onRefresh;
  final VoidCallback onFoodOrderPressed;

  const _HomeTab({
    required this.onRefresh,
    required this.onFoodOrderPressed,
  });

  @override
  State<_HomeTab> createState() => __HomeTabState();
}

class __HomeTabState extends State<_HomeTab> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final List<Map<String, dynamic>> _todaySchedule = [];
  final List<Map<String, dynamic>> _collegeNews = [];
  bool _loading = true;
  bool _hasScheduleData = false;
  bool _hasNewsData = false;
  String? _scheduleError;
  String? _newsError;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final response = await _supabase
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .maybeSingle();

        if (response != null) {
          setState(() {
            _userProfile = Map<String, dynamic>.from(response);
          });
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля в _HomeTab: $e');
    }

    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _scheduleError = null;
      _newsError = null;
    });

    await Future.wait([
      _loadSchedule(),
      _loadNews(),
    ]);

    setState(() => _loading = false);
  }

  Future<void> _loadSchedule() async {
    final studentGroup = _userProfile?['student_group'];
    if (studentGroup == null || studentGroup.toString().isEmpty) {
      setState(() {
        _hasScheduleData = false;
        _scheduleError = 'Группа не указана';
      });
      return;
    }

    try {
      final today = DateTime.now();
      final days = [
        'Понедельник',
        'Вторник',
        'Среда',
        'Четверг',
        'Пятница',
        'Суббота',
        'Воскресенье'
      ];
      final todayName = days[today.weekday - 1];

      final scheduleResponse = await _supabase
          .from('schedule')
          .select('''
          id, subject, teacher, room, 
          start_time, end_time, day_of_week
        ''')
          .eq('group_name', studentGroup)
          .eq('day_of_week', todayName)
          .order('start_time')
          .timeout(const Duration(seconds: 5));

      setState(() {
        _todaySchedule.clear();
        if (scheduleResponse != null) {
          _todaySchedule.addAll(List<Map<String, dynamic>>.from(scheduleResponse));
        }
        _hasScheduleData = _todaySchedule.isNotEmpty;
        _scheduleError = null;
      });
    } on TimeoutException {
      setState(() {
        _hasScheduleData = false;
        _scheduleError = 'Таймаут загрузки расписания';
      });
    } catch (error) {
      debugPrint('Error loading schedule: $error');
      setState(() {
        _hasScheduleData = false;
        _scheduleError = 'Ошибка загрузки расписания';
      });
    }
  }

  Future<void> _loadNews() async {
    try {
      final newsResponse = await _supabase
          .from('news')
          .select('''
          id, title, content, created_at, author_name, image_url, 
          priority, is_published, published_at
        ''')
          .eq('is_published', true)
          .order('published_at', ascending: false)
          .limit(5)
          .timeout(const Duration(seconds: 5));

      setState(() {
        _collegeNews.clear();
        if (newsResponse != null) {
          _collegeNews.addAll(List<Map<String, dynamic>>.from(newsResponse));
        }
        _hasNewsData = _collegeNews.isNotEmpty;
        _newsError = null;
      });
    } on TimeoutException {
      setState(() {
        _hasNewsData = false;
        _newsError = 'Таймаут загрузки новостей';
      });
    } catch (error) {
      debugPrint('Error loading news: $error');
      setState(() {
        _hasNewsData = false;
        _newsError = 'Ошибка загрузки новостей';
      });
    }
  }

  Widget _buildScheduleCard() {
    if (_loading) {
      return ModernCard(
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            const Text('Загрузка расписания...'),
          ],
        ),
      );
    }

    if (_scheduleError != null) {
      return ModernCard(
        child: Column(
          children: [
            Icon(Icons.schedule_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(_scheduleError!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadSchedule,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (!_hasScheduleData) {
      return ModernCard(
        child: Column(
          children: [
            Icon(Icons.schedule_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('Сегодня занятий нет'),
          ],
        ),
      );
    }

    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Расписание на сегодня',
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                iconSize: 20,
                onPressed: _loadSchedule,
                tooltip: 'Обновить расписание',
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._todaySchedule.map((lesson) {
            final startTime = lesson['start_time']?.toString().substring(0, 5) ?? '';
            final endTime = lesson['end_time']?.toString().substring(0, 5) ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$startTime - $endTime',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson['subject'] ?? 'Предмет',
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${lesson['teacher'] ?? 'Преподаватель'} • Ауд. ${lesson['room'] ?? '—'}',
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              // Здесь можно добавить навигацию к полному расписанию
            },
            child: const Text('Все расписание'),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard() {
    if (_loading) {
      return ModernCard(
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            const Text('Загрузка новостей...'),
          ],
        ),
      );
    }

    if (_newsError != null) {
      return ModernCard(
        child: Column(
          children: [
            Icon(Icons.newspaper_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(_newsError!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadNews,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (!_hasNewsData) {
      return ModernCard(
        child: Column(
          children: [
            Icon(Icons.newspaper_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('Новостей пока нет'),
          ],
        ),
      );
    }

    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Новости колледжа',
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                iconSize: 20,
                onPressed: _loadNews,
                tooltip: 'Обновить новости',
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._collegeNews.map((news) {
            final date = news['created_at'] != null
                ? DateFormat('dd.MM.yyyy').format(
              DateTime.parse(news['created_at']),
            )
                : '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (news['title'] != null)
                    Text(
                      news['title']!,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (news['content'] != null)
                    Text(
                      news['content']!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        news['author_name'] ?? 'Администрация',
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.grey[500],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        date,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Приветствие
              Text(
                'Добро пожаловать!',
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Сегодня ${DateFormat('dd MMMM yyyy', 'ru_RU').format(DateTime.now())}',
                style: AppTypography.bodyLarge.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),

              // Карточка "Расписание на сегодня"
              _buildScheduleCard(),

              const SizedBox(height: 16),

              // Новости колледжа
              _buildNewsCard(),

              const SizedBox(height: 16),

              // Быстрый доступ
              ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Быстрый доступ',
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _QuickActionButton(
                          icon: Icons.restaurant,
                          label: 'Заказать еду',
                          onTap: widget.onFoodOrderPressed,
                        ),
                        _QuickActionButton(
                          icon: Icons.groups,
                          label: 'Кружки',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const CirclesScreen(),
                              ),
                            );
                          },
                        ),
                        _QuickActionButton(
                          icon: Icons.settings,
                          label: 'Настройки',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                        _QuickActionButton(
                          icon: Icons.info,
                          label: 'О приложении',
                          onTap: () {
                            showAboutDialog(
                              context: context,
                              applicationName: 'BOLASHAQ',
                              applicationVersion: '2.0.0',
                              applicationLegalese: '© ${DateTime.now().year} Колледж BOLASHAQ',
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// Кнопка быстрого действия
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.labelMedium,
            ),
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