import 'dart:async';

import 'package:bolashaq/screens/staff_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';

// screens
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/seller_home_screen.dart';
import 'screens/coach_home_screen.dart';
import 'screens/coupons_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/sport_sections_screen.dart';
import 'screens/clubs_screen.dart';
import 'screens/circles_screen.dart'; // ДОБАВЛЕН новый экран
import 'screens/food_preorder_screen.dart';
import 'screens/qr_redeem_screen.dart';
import 'screens/settings_screen.dart';

// theme
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://kofbizzblfbopsahanby.supabase.co',
    anonKey: 'sb_publishable_4l9gN4qdadxtNjgRFxqmkg_Jd7Oh6oe',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  await initializeDateFormatting('ru_RU', null);
  await initializeDateFormatting('en_US', null);

  runApp(const CollegeApp());
}

class CollegeApp extends StatelessWidget {
  const CollegeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BOLASHAQ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Inter',
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 2),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        fontFamily: 'Inter',
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 2),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const RootGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
        '/admin': (_) => const AdminDashboardScreen(),
        '/seller': (_) => const SellerHomeScreen(),
        '/coach': (_) => const CoachHomeScreen(),
        '/tickets': (_) => const CouponsScreen(),
        '/schedule': (_) => const ScheduleScreen(),
        '/sports-sections': (_) => const SportSectionsScreen(),
        '/clubs': (_) => const ClubsScreen(),
        '/circles': (_) => const CirclesScreen(), // ДОБАВЛЕН новый маршрут
        '/food-order': (_) => const FoodPreorderScreen(),
        '/scanner': (_) => const QrRedeemScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/staff': (_) => const StaffHomeScreen(),
      },
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _profile;
  bool _isBootstrapping = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();

    _supabase.auth.onAuthStateChange.listen((event) {
      final user = _supabase.auth.currentUser;
      if (user?.id != _profile?['id']) {
        _bootstrap();
      }
    });
  }

  Future<void> _bootstrap() async {
    if (_isBootstrapping) return;

    _isBootstrapping = true;
    debugPrint('[RootGate] Начало загрузки профиля...');

    if (mounted) {
      setState(() {
        _loading = true;
        _profile = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;
      debugPrint('[RootGate] Текущий пользователь Auth: ${user?.id}');

      if (user == null) {
        debugPrint('[RootGate] Пользователь не аутентифицирован');
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }

      // Пробуем получить профиль несколько раз с задержками
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          debugPrint('[RootGate] Попытка ${attempt + 1} загрузить профиль для UID: ${user.id}');

          // ЗАГРУЖАЕМ ПОЛНЫЙ ПРОФИЛЬ ИЗ ТАБЛИЦЫ profiles
          final response = await _supabase
              .from('profiles')
              .select('''
                id, full_name, email, role, 
                student_group, student_speciality,
                iin, category, phone, date_of_birth,
                verified_for_food, balance, avatar_url,
                username, created_at, updated_at
              ''')
              .eq('id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));

          if (response != null) {
            _profile = Map<String, dynamic>.from(response);

            // Проверяем email в профиле
            final profileEmail = _profile?['email'];
            final authEmail = user.email;

            // Если email в профиле не совпадает с email в auth, обновляем
            if (profileEmail == null || profileEmail.isEmpty || profileEmail != authEmail) {
              debugPrint('[RootGate] Обновляем email в профиле: $authEmail');
              await _supabase
                  .from('profiles')
                  .update({
                'email': authEmail,
                'updated_at': DateTime.now().toIso8601String(),
              })
                  .eq('id', user.id);
              _profile!['email'] = authEmail;
            }

            // Проверяем имя пользователя
            final currentName = _profile?['full_name'] as String?;
            if (currentName == null || currentName.isEmpty ||
                (authEmail != null && currentName == authEmail.split('@').first)) {
              // Генерируем имя из email или используем значение по умолчанию
              String newName;
              if (authEmail != null) {
                final emailPart = authEmail.split('@').first;
                if (emailPart.contains('_')) {
                  // Преобразуем "user_d80925fe" в "User D80925fe"
                  newName = emailPart
                      .replaceAll('_', ' ')
                      .split(' ')
                      .map((part) => part.isNotEmpty ?
                  '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}' : '')
                      .join(' ');
                } else {
                  newName = emailPart;
                }
              } else {
                newName = 'Новый пользователь';
              }

              debugPrint('[RootGate] Обновляем имя в профиле: $newName');
              await _supabase
                  .from('profiles')
                  .update({
                'full_name': newName,
                'updated_at': DateTime.now().toIso8601String(),
              })
                  .eq('id', user.id);
              _profile!['full_name'] = newName;
            }

            debugPrint('[RootGate] Профиль найден: ${_profile?['full_name']} (${_profile?['role']})');
            break;
          } else {
            debugPrint('[RootGate] Профиль не найден, создаем новый...');

            // Создаем новый профиль
            final email = user.email ?? 'user_${user.id.substring(0, 8)}@edubolashaq.com';
            final newProfile = {
              'id': user.id,
              'full_name': _generateNameFromEmail(email),
              'email': email,
              'role': 'student',
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            };

            try {
              final insertResponse = await _supabase
                  .from('profiles')
                  .upsert(newProfile, onConflict: 'id')
                  .select()
                  .single()
                  .timeout(const Duration(seconds: 5));

              _profile = Map<String, dynamic>.from(insertResponse);
              debugPrint('[RootGate] Профиль создан: ${_profile?['full_name']}');
              break;
            } catch (e) {
              if (e is PostgrestException && e.code == '23505') {
                debugPrint('[RootGate] Обнаружен дубликат, пробуем загрузить профиль...');
                await Future.delayed(const Duration(milliseconds: 500));
                continue;
              }
              rethrow;
            }
          }
        } on TimeoutException catch (_) {
          debugPrint('[RootGate] Таймаут при загрузке профиля, попытка ${attempt + 1}');
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          debugPrint('[RootGate] Ошибка при попытке $attempt: $e');
          if (attempt == 2) rethrow;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      debugPrint('[RootGate] Финальная ошибка загрузки профиля: $e');
    } finally {
      _isBootstrapping = false;
      debugPrint('[RootGate] Загрузка завершена. Профиль: ${_profile != null ? "Успешно" : "Не удалось"}');

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _generateNameFromEmail(String email) {
    final emailPart = email.split('@').first;

    // Если email в формате "user_d80925fe"
    if (emailPart.contains('_')) {
      return emailPart
          .replaceAll('_', ' ')
          .split(' ')
          .map((part) => part.isNotEmpty ?
      '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}' : '')
          .join(' ');
    }

    // Если email в формате "admin@gmail.com"
    return emailPart[0].toUpperCase() + emailPart.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SplashScreen();
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      return const LoginScreen();
    }

    if (_profile == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppColors.error,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Не удалось загрузить профиль',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Пожалуйста, попробуйте войти снова',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    _supabase.auth.signOut();
                  },
                  child: const Text('Выйти и попробовать снова'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final role = _profile!['role'] as String? ?? 'student';
    debugPrint('[RootGate] Определена роль: $role');
    debugPrint('[RootGate] Имя пользователя: ${_profile!['full_name']}');
    debugPrint('[RootGate] Email: ${_profile!['email']}');
    debugPrint('[RootGate] Группа: ${_profile!['student_group']}');

    // Передаем профиль в соответствующие экраны
    switch (role.toLowerCase()) {
      case 'admin':
        return const AdminDashboardScreen();
      case 'seller':
      case 'cashier':
        return const SellerHomeScreen();
      case 'coach':
      case 'тренер':
      case 'trainer':
        return const CoachHomeScreen();
      case 'teacher':
      case 'преподаватель':
        return HomeScreen(initialProfile: _profile);
      case 'staff':
      case 'персонал':
        return const StaffHomeScreen();
      case 'student':
      case 'студент':
      default:
        return HomeScreen(initialProfile: _profile);
    }
  }
}