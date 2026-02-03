// lib/screens/login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _errorMessage;
  int _failedAttempts = 0;
  DateTime? _lastAttemptTime;

  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  final _supabase = Supabase.instance.client;
  Timer? _rateLimitTimer;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });

    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _rateLimitTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('Error loading saved credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    if (!_rememberMe) return;
  }

  void _handleLogin() {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_checkRateLimit()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _performLogin();
  }

  bool _checkRateLimit() {
    final now = DateTime.now();

    if (_failedAttempts >= 5) {
      if (_lastAttemptTime != null &&
          now.difference(_lastAttemptTime!) < const Duration(minutes: 15)) {
        _showRateLimitDialog();
        return true;
      } else {
        _failedAttempts = 0;
      }
    }

    if (_lastAttemptTime != null &&
        now.difference(_lastAttemptTime!) < const Duration(seconds: 1)) {
      return true;
    }

    _lastAttemptTime = now;
    return false;
  }

  Future<void> _performLogin() async {
    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      if (username.isEmpty) {
        _handleError('Введите логин');
        return;
      }

      debugPrint('Поиск пользователя: $username');

      // Вариант 1: Используем новую таблицу login_lookup
      final response = await _supabase
          .from('login_lookup')
          .select('email')
          .eq('username', username)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      // Вариант 2: Или используем функцию
      // final response = await _supabase.rpc(
      //   'get_user_email',
      //   params: {'user_username': username},
      // );

      debugPrint('Результат запроса: ${response.toString()}');

      if (response == null || response['email'] == null) {
        _handleError('Пользователь с логином "$username" не найден');
        return;
      }

      final email = response['email'] as String;
      debugPrint('Найден email: $email');

      // Пробуем войти
      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 30));

      if (authResponse.user != null) {
        debugPrint('Успешный вход для: ${authResponse.user!.id}');
        await _handleSuccessfulLogin();
      }
    } on TimeoutException catch (_) {
      _handleError('Таймаут подключения. Проверьте интернет.');
    } on AuthException catch (e) {
      _handleAuthError(e);
    } on PostgrestException catch (e) {
      debugPrint('Ошибка Postgrest: ${e.message}');

      _handleError('Ошибка доступа к базе данных (код: ${e.code})');
    } catch (e, stackTrace) {
      debugPrint('Непредвиденная ошибка: $e');
      debugPrint('StackTrace: $stackTrace');
      _handleError('Ошибка соединения с сервером');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSuccessfulLogin() async {
    _failedAttempts = 0;
    await _saveCredentials();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
        const RootGate(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _handleAuthError(AuthException e) {
    _failedAttempts++;

    final errorMessage = switch (e.message) {
      'Invalid login credentials' => 'Неверный логин или пароль',
      'Email not confirmed' => 'Email не подтверждён. Обратитесь к администратору.',
      'User not found' => 'Пользователь не найден',
      'Too many requests' => 'Слишком много попыток. Попробуйте позже.',
      String() => 'Ошибка аутентификации: ${e.message}',
    };

    setState(() => _errorMessage = errorMessage);
  }

  void _handleError(String message) {
    _failedAttempts++;
    setState(() => _errorMessage = message);
  }

  void _handlePasswordReset() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Восстановление пароля'),
        content: const Text('Чтобы поменять пароль обратитесь в поддержку.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showRateLimitDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Слишком много попыток'),
        content: const Text(
          'Вы превысили лимит попыток входа. '
              'Пожалуйста, подождите 15 минут и попробуйте снова.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAccountInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Получение аккаунта'),
        content: const SingleChildScrollView(
          child: Text(
            'Учетные записи создаются только администрацией колледжа.\n\n'
                'Для получения доступа обратитесь в деканат или к системному администратору.\n\n'
                'Если у вас есть учетные данные, но возникли проблемы со входом, '
                'обратитесь в службу поддержки.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Добавить логику для связи с поддержкой
            },
            child: const Text('Связаться'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDarkMode
          ? SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      )
          : SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Opacity(
                opacity: _opacityAnimation.value,
                child: Transform.translate(
                  offset: _slideAnimation.value,
                  child: child,
                ),
              );
            },
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).size.height * 0.05,
                bottom: MediaQuery.of(context).size.height * 0.05,
                left: AppSpacing.xl,
                right: AppSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.white,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Image.asset(
                              'assets/icon/icon.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Карагандинский высший колледж Bolashaq',
                          style: AppTypography.headlineMedium.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 20, // Уменьшаем размер шрифта для лучшего отображения
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Вход для студентов и преподавателей',
                          style: AppTypography.bodyMedium.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xxxl),

                    Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Логин',
                                style: AppTypography.labelLarge,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextFormField(
                                controller: _usernameController,
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  hintText: 'Введите ваш логин',
                                  prefixIcon: const Icon(Icons.person_rounded),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.lg,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Введите логин';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) {
                                  FocusScope.of(context)
                                      .requestFocus(_passwordFocusNode);
                                },
                              ),

                              const SizedBox(height: AppSpacing.lg),

                              Text(
                                'Пароль',
                                style: AppTypography.labelLarge,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextFormField(
                                controller: _passwordController,
                                focusNode: _passwordFocusNode,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  hintText: 'Введите пароль',
                                  prefixIcon: const Icon(Icons.lock_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.lg,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Введите пароль';
                                  }
                                  if (value.length < 6) {
                                    return 'Минимум 6 символов';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _handleLogin(),
                              ),

                              const SizedBox(height: AppSpacing.lg),

                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) {
                                      setState(() {
                                        _rememberMe = value ?? false;
                                      });
                                    },
                                  ),
                                  Text(
                                    'Запомнить меня',
                                    style: AppTypography.bodyMedium,
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: _handlePasswordReset,
                                    child: Text(
                                      'Забыли пароль?',
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              if (_errorMessage != null) ...[
                                const SizedBox(height: AppSpacing.md),
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withOpacity(0.1),
                                    borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(
                                      color: AppColors.error.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.error,
                                        size: 20,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: AppTypography.bodyMedium
                                              .copyWith(
                                            color: AppColors.error,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: AppSpacing.xl),

                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.lg,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                                    : Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.login_rounded),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      'Войти',
                                      style: AppTypography.labelLarge.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: AppSpacing.xl),

                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: theme.colorScheme.outline
                                          .withOpacity(0.3),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md),
                                    child: Text(
                                      'или',
                                      style: AppTypography.bodySmall,
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: theme.colorScheme.outline
                                          .withOpacity(0.3),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: AppSpacing.lg),

                              OutlinedButton(
                                onPressed: _showAccountInfo,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.lg,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.info_outline_rounded),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      'Как получить аккаунт?',
                                      style: AppTypography.labelLarge.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xxxl),

                    Column(
                      children: [
                        Text(
                          'Только для студентов и преподавателей',
                          style: AppTypography.bodySmall.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Версия 1.0.0 • © ${DateTime.now().year}',
                          style: AppTypography.bodySmall.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}