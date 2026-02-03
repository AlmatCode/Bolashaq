/*
  Красивый Splash Screen для BOLASHAQ College App
  Только дизайн и базовая загрузка
*/

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Контроллеры анимации
  late final AnimationController _logoController;
  late final Animation<double> _logoAnimation;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Состояние загрузки
  bool _isLoading = true;
  bool _hasError = false;
  String _statusMessage = 'Загрузка приложения...';

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startLoading();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    // Анимация логотипа - плавное появление с увеличением
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Анимация текста - плавное появление
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Пульсирующая анимация для элементов
    _pulseController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _logoAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  // В методе _startLoading добавляем проверку mounted
  Future<void> _startLoading() async {
    // Запускаем анимации
    await Future.delayed(const Duration(milliseconds: 300));

    // Проверяем mounted перед анимациями
    if (!mounted) return;

    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    _fadeController.forward();

    try {
      // Проверяем соединение с Supabase
      _updateStatus('Проверка соединения...');

      // Добавляем проверку mounted перед каждым setState
      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 800));

      // Проверяем аутентификацию
      _updateStatus('Проверка авторизации...');

      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 600));

      final user = _supabase.auth.currentUser;

      // Завершаем загрузку
      _updateStatus('Завершение...');

      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // Переход на следующий экран
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
            user != null ? const HomeScreen() : const LoginScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }

    } catch (error) {
      if (!mounted) return;

      setState(() {
        _hasError = true;
        _statusMessage = 'Ошибка загрузки';
      });

      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        _retryLoading();
      }
    }
  }

// Добавляем проверку в _updateStatus
  void _updateStatus(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
  }

// В _retryLoading также добавляем проверку
  void _retryLoading() {
    if (!mounted) return;

    setState(() {
      _hasError = false;
      _isLoading = true;
      _statusMessage = 'Повторная загрузка...';
    });

    _startLoading();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF2196F3).withOpacity(0.95),
                const Color(0xFF1976D2).withOpacity(0.95),
                const Color(0xFF0D47A1).withOpacity(0.95),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Фоновые элементы
              _buildBackgroundElements(),

              // Основной контент
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Анимированный логотип
                      ScaleTransition(
                        scale: _logoAnimation,
                        child: ScaleTransition(
                          scale: _pulseAnimation,
                          child: _buildLogo(),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Название приложения с анимацией
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          children: [
                            Text(
                              'BOLASHAQ',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(2, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'College App',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(0.9),
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Область статуса
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: _buildStatusArea(),
                      ),

                      const SizedBox(height: 32),

                      // Версия приложения
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Text(
                          'Версия 1.0.0',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Оверлей ошибки
              if (_hasError) _buildErrorOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundElements() {
    return Stack(
      children: [
        // Большие круги на заднем плане
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.03),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -150,
          left: -100,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.02),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // Геометрические фигуры
        Positioned(
          top: 100,
          left: 50,
          child: Transform.rotate(
            angle: pi / 4,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 80,
          right: 60,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 2,
              ),
            ),
          ),
        ),

        // Точки на заднем плане
        ...List.generate(20, (index) {
          final random = Random();
          return Positioned(
            left: random.nextDouble() * MediaQuery.of(context).size.width,
            top: random.nextDouble() * MediaQuery.of(context).size.height,
            child: Container(
              width: random.nextDouble() * 3 + 1,
              height: random.nextDouble() * 3 + 1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(random.nextDouble() * 0.2 + 0.1),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.05),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.1),
            blurRadius: 30,
            spreadRadius: -5,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Внешнее свечение
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.1),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),

            // Основная иконка
            Icon(
              Icons.school_rounded,
              size: 60,
              color: Colors.white.withOpacity(0.9),
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(2, 2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusArea() {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Сообщение о статусе
          Text(
            _statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Индикатор загрузки или иконка ошибки
          if (_isLoading && !_hasError)
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withOpacity(0.8),
                ),
                backgroundColor: Colors.white.withOpacity(0.1),
              ),
            )
          else if (_hasError)
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: const Color(0xFFFF6B6B).withOpacity(0.9),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.black.withOpacity(0.9),
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: const Color(0xFFFF6B6B),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Нет соединения',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Проверьте подключение к интернету',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _retryLoading,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Повторить',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}