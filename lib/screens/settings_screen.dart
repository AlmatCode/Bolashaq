import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Состояние
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _settingsId;

  // Данные пользователя
  Map<String, dynamic>? _profile;
  PackageInfo? _packageInfo;

  // Настройки (соответствуют столбцам user_settings)
  bool _notificationsEnabled = true;
  bool _biometricAuthEnabled = false;
  bool _autoSyncEnabled = true;
  bool _dataSavingMode = false;
  String _language = 'ru';
  String _theme = 'system';
  bool _showOnlineStatus = true;
  bool _allowProfileView = true;
  bool _shareAnalytics = true;

  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
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

      // Загружаем профиль
      final profileResp = await _supabase
          .from('profiles')
          .select('''
          id, full_name, email, student_id, phone, 
          role, student_group, verified_for_food, balance, avatar_url
        ''')
          .eq('id', user.id)
          .single();

      _profile = Map<String, dynamic>.from(profileResp);

      // Загружаем настройки пользователя
      final settingsResp = await _supabase
          .from('user_settings')
          .select('''
          id, notifications, biometrics, auto_sync, 
          data_saving_mode, language, theme,
          show_online_status, allow_profile_view, share_analytics
        ''')
          .eq('user_id', user.id)
          .maybeSingle();

      if (settingsResp != null) {
        // Сохраняем ID записи настроек
        _settingsId = settingsResp['id'] as String?;

        // ИСПРАВЛЕНИЕ: используем правильные имена столбцов из таблицы user_settings
        _notificationsEnabled = settingsResp['notifications'] ?? true;
        _biometricAuthEnabled = settingsResp['biometrics'] ?? false;
        _autoSyncEnabled = settingsResp['auto_sync'] ?? true;
        _dataSavingMode = settingsResp['data_saving_mode'] ?? false;
        _language = settingsResp['language'] ?? 'ru';
        _theme = settingsResp['theme'] ?? 'system';
        _showOnlineStatus = settingsResp['show_online_status'] ?? true;
        _allowProfileView = settingsResp['allow_profile_view'] ?? true;
        _shareAnalytics = settingsResp['share_analytics'] ?? true;
      } else {
        // Если настроек нет, создаем запись по умолчанию
        await _createDefaultSettings(user.id);
        // После создания перезагружаем настройки
        await _reloadSettings(user.id);
      }

      // Получаем информацию о пакете
      _packageInfo = await PackageInfo.fromPlatform();
    } on PostgrestException catch (e) {
      setState(() => _error = 'Ошибка базы данных: ${e.message}');
    } catch (e) {
      setState(() => _error = 'Ошибка загрузки настроек: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Новый метод для перезагрузки настроек
  Future<void> _reloadSettings(String userId) async {
    try {
      final settingsResp = await _supabase
          .from('user_settings')
          .select('id, notifications, biometrics, auto_sync, data_saving_mode, language, theme')
          .eq('user_id', userId)
          .maybeSingle();

      if (settingsResp != null && mounted) {
        _settingsId = settingsResp['id'] as String?;
        _notificationsEnabled = settingsResp['notifications'] ?? true;
        _biometricAuthEnabled = settingsResp['biometrics'] ?? false;
        _autoSyncEnabled = settingsResp['auto_sync'] ?? true;
        _dataSavingMode = settingsResp['data_saving_mode'] ?? false;
        _language = settingsResp['language'] ?? 'ru';
        _theme = settingsResp['theme'] ?? 'system';
      }
    } catch (e) {
      print('Ошибка перезагрузки настроек: $e');
    }
  }

  Future<void> _createDefaultSettings(String userId) async {
    try {
      final response = await _supabase
          .from('user_settings')
          .insert({
        'user_id': userId,
        'notifications': true,
        'biometrics': false,
        'biometric_auth': false,
        'auto_sync': true,
        'data_saving_mode': false,
        'language': 'ru',
        'theme': 'system',
        'show_online_status': true,
        'allow_profile_view': true,
        'share_analytics': true,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      })
          .select('id') // Возвращаем ID созданной записи
          .single();

      if (response != null && mounted) {
        _settingsId = response['id'] as String?;
      }
    } on PostgrestException catch (e) {
      // Если ошибка "duplicate key", значит запись уже существует
      if (e.code == '23505') {
        print('Запись настроек уже существует для пользователя $userId');
        // Перезагружаем существующие настройки
        await _reloadSettings(userId);
      } else {
        print('Ошибка создания настроек по умолчанию: ${e.message}');
        // Пробуем обновить существующую запись
        await _updateExistingSettings(userId);
      }
    } catch (e) {
      print('Ошибка создания настроек по умолчанию: $e');
    }
  }

// Новый метод для обновления существующих настроек
  Future<void> _updateExistingSettings(String userId) async {
    try {
      final response = await _supabase
          .from('user_settings')
          .update({
        'notifications': true,
        'biometrics': false,
        'biometric_auth': false,
        'auto_sync': true,
        'data_saving_mode': false,
        'language': 'ru',
        'theme': 'system',
        'show_online_status': true,
        'allow_profile_view': true,
        'share_analytics': true,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('user_id', userId)
          .select('id')
          .maybeSingle();

      if (response != null && mounted) {
        _settingsId = response['id'] as String?;
      }
    } catch (e) {
      print('Ошибка обновления существующих настроек: $e');
    }
  }

  Future<void> _saveSettings() async {
    if (!mounted) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = {
        'user_id': user.id,
        'notifications': _notificationsEnabled,
        'biometrics': _biometricAuthEnabled,
        'biometric_auth': _biometricAuthEnabled,
        'auto_sync': _autoSyncEnabled,
        'data_saving_mode': _dataSavingMode,
        'language': _language,
        'theme': _theme,
        'show_online_status': _showOnlineStatus,
        'allow_profile_view': _allowProfileView,
        'share_analytics': _shareAnalytics,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Если у нас есть ID записи, добавляем его в данные
      if (_settingsId != null) {
        data['id'] = _settingsId!;
      }

      final response = await _supabase
          .from('user_settings')
          .upsert(data) // Используем upsert вместо insert
          .select('id')
          .single();

      // Обновляем ID если он был создан
      if (response != null) {
        _settingsId = response['id'] as String?;
      }

      if (!mounted) return;
      context.showSnackBar('Настройки сохранены');
    } on PostgrestException catch (e) {
      // Обработка ошибки дублирования ключа
      if (e.code == '23505') {
        setState(() => _error = 'Настройки уже существуют. Пожалуйста, обновите страницу.');
        // Пробуем обновить существующие настройки
        await _updateExistingSettings(_supabase.auth.currentUser!.id);
      } else {
        setState(() => _error = 'Ошибка базы данных: ${e.message}');
      }
      if (mounted) {
        context.showSnackBar('Ошибка сохранения настроек', isError: true);
      }
    } catch (e) {
      setState(() => _error = 'Ошибка сохранения: ${e.toString()}');
      if (mounted) {
        context.showSnackBar('Ошибка сохранения настроек', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

// Добавьте метод для принудительного сброса настроек (на случай проблем)
  Future<void> _resetSettings() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сброс настроек'),
        content: const Text('Вы уверены, что хотите сбросить настройки к значениям по умолчанию?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performResetSettings();
            },
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
  }

  Future<void> _performResetSettings() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Удаляем существующие настройки
      await _supabase
          .from('user_settings')
          .delete()
          .eq('user_id', user.id);

      // Сбрасываем локальные настройки
      setState(() {
        _settingsId = null;
        _notificationsEnabled = true;
        _biometricAuthEnabled = false;
        _autoSyncEnabled = true;
        _dataSavingMode = false;
        _language = 'ru';
        _theme = 'system';
        _showOnlineStatus = true;
        _allowProfileView = true;
        _shareAnalytics = true;
      });

      // Создаем новые настройки по умолчанию
      await _createDefaultSettings(user.id);

      if (mounted) {
        context.showSnackBar('Настройки сброшены');
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Ошибка сброса настроек', isError: true);
      }
    }
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход из аккаунта'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performLogout();
            },
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    try {
      // Сначала обновляем last_login в профиле
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase
            .from('profiles')
            .update({'last_login': DateTime.now().toIso8601String()})
            .eq('id', user.id);
      }

      // Затем выходим из auth
      await _supabase.auth.signOut();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Ошибка выхода: $e', isError: true);
      }
    }
  }

  Future<void> _deleteAccount() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление аккаунта'),
        content: const Text(
          'Вы уверены, что хотите удалить аккаунт? Это действие нельзя отменить. '
              'Все ваши данные будут безвозвратно удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performAccountDeletion();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<void> _performAccountDeletion() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // В production здесь должен быть вызов Edge Function для безопасного удаления
      await _supabase.auth.admin.deleteUser(user.id);

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Ошибка удаления аккаунта', isError: true);
      }
    }
  }

  Future<void> _changePassword() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _ChangePasswordModal(),
    );
  }

  Future<void> _contactSupport() async {
    final email = 'support@bolashaq.edu.kz';
    final subject = 'Поддержка: ${_profile?['full_name']}';
    final body = 'Версия приложения: ${_packageInfo?.version}\n'
        'ID пользователя: ${_profile?['id']}\n'
        'Роль: ${_profile?['role']}\n'
        'Группа: ${_profile?['student_group']}\n\n'
        'Опишите вашу проблему:';

    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      context.showSnackBar('Не удалось открыть почтовый клиент', isError: true);
    }
  }

  Future<void> _shareApp() async {
    try {
      await Share.share(
        'Скачайте приложение Колледж Bolashaq для управления расписанием, питанием и секциями!',
        subject: 'Приложение Колледж Bolashaq',
      );
    } catch (e) {
      context.showSnackBar('Ошибка при попытке поделиться', isError: true);
    }
  }

  Widget _buildProfileHeader() {
    final initials = (_profile?['full_name'] as String? ?? '?')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0])
        .take(2)
        .join()
        .toUpperCase();

    return ModernCard(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppGradients.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: AppTypography.titleLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profile?['full_name'] as String? ?? 'Не указано',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _profile?['email'] as String? ?? 'Нет email',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _profile?['role'] == 'admin'
                            ? 'Администратор'
                            : _profile?['role'] == 'staff'
                            ? 'Персонал'
                            : _profile?['role'] == 'teacher'
                            ? 'Преподаватель'
                            : _profile?['role'] == 'seller'
                            ? 'Продавец'
                            : 'Студент',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (_profile?['student_group'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _profile?['student_group'] as String,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    if (_profile?['verified_for_food'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: 12, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text(
                              'Верифицирован',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSection({
    required String title,
    required List<Widget> children,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: AppTypography.titleSmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ModernCard(
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                )),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              onChanged(v);
              _saveSettings();
            },
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSetting() {
    final languageNames = {
      'ru': 'Русский',
      'en': 'English',
      'kz': 'Қазақша',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.language, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Язык', style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                )),
                Text(
                  languageNames[_language] ?? 'Русский',
                  style: AppTypography.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _language = value);
              _saveSettings();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'ru', child: Text('Русский')),
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'kz', child: Text('Қазақша')),
            ],
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.arrow_drop_down, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSetting() {
    final themeNames = {
      'system': 'Системная',
      'light': 'Светлая',
      'dark': 'Темная',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.palette, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Тема', style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                )),
                Text(
                  themeNames[_theme] ?? 'Системная',
                  style: AppTypography.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _theme = value);
              _saveSettings();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'system', child: Text('Системная')),
              PopupMenuItem(value: 'light', child: Text('Светлая')),
              PopupMenuItem(value: 'dark', child: Text('Темная')),
            ],
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.arrow_drop_down, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySwitchSetting({
    required String key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _buildSwitchSetting(
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
      icon: Icons.privacy_tip,
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    bool destructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: destructive
            ? Theme.of(context).colorScheme.error
            : color ?? Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        title,
        style: AppTypography.bodyMedium.copyWith(
          color: destructive
              ? Theme.of(context).colorScheme.error
              : null,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
        subtitle,
        style: AppTypography.bodySmall.copyWith(
          color: destructive
              ? Theme.of(context).colorScheme.error.withOpacity(0.7)
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
      )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Text(
            'О приложении',
            style: AppTypography.titleSmall.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ModernCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info, color: AppColors.primary),
                title: const Text('Версия'),
                subtitle: Text(_packageInfo?.version ?? '1.0.0'),
              ),
              ListTile(
                leading: const Icon(Icons.share, color: AppColors.primary),
                title: const Text('Поделиться приложением'),
                onTap: _shareApp,
              ),
              ListTile(
                leading: const Icon(Icons.star, color: AppColors.primary),
                title: const Text('Оценить приложение'),
                onTap: () {
                  // TODO: Реализовать переход в магазин приложений
                },
              ),
              ListTile(
                leading: const Icon(Icons.description, color: AppColors.primary),
                title: const Text('Пользовательское соглашение'),
                onTap: () {
                  // TODO: Реализовать просмотр соглашения
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip, color: AppColors.primary),
                title: const Text('Политика конфиденциальности'),
                onTap: () {
                  // TODO: Реализовать просмотр политики
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Настройки',
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
              onPressed: _initializeSettings,
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _initializeSettings,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Уведомления и внешний вид',
              icon: Icons.notifications,
              children: [
                _buildSwitchSetting(
                  title: 'Push-уведомления',
                  subtitle: 'Получать уведомления о событиях',
                  value: _notificationsEnabled,
                  onChanged: (v) => setState(() => _notificationsEnabled = v),
                  icon: Icons.notifications,
                ),
                _buildSwitchSetting(
                  title: 'Автосинхронизация',
                  subtitle: 'Автоматически синхронизировать данные',
                  value: _autoSyncEnabled,
                  onChanged: (v) => setState(() => _autoSyncEnabled = v),
                  icon: Icons.sync,
                ),
                _buildLanguageSetting(),
                _buildThemeSetting(),
              ],
            ),

            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Конфиденциальность',
              icon: Icons.privacy_tip,
              children: [
                _buildPrivacySwitchSetting(
                  key: 'show_online_status',
                  title: 'Показывать статус "В сети"',
                  subtitle: 'Другие пользователи видят ваш онлайн статус',
                  value: _showOnlineStatus,
                  onChanged: (v) => setState(() => _showOnlineStatus = v),
                ),
                _buildPrivacySwitchSetting(
                  key: 'allow_profile_view',
                  title: 'Разрешить просмотр профиля',
                  subtitle: 'Другие пользователи могут просматривать ваш профиль',
                  value: _allowProfileView,
                  onChanged: (v) => setState(() => _allowProfileView = v),
                ),
                _buildPrivacySwitchSetting(
                  key: 'share_analytics',
                  title: 'Отправлять анонимную статистику',
                  subtitle: 'Помогает улучшать приложение',
                  value: _shareAnalytics,
                  onChanged: (v) => setState(() => _shareAnalytics = v),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Безопасность',
              icon: Icons.security,
              children: [
                _buildSwitchSetting(
                  title: 'Биометрическая авторизация',
                  subtitle: 'Использовать Face ID / Touch ID',
                  value: _biometricAuthEnabled,
                  onChanged: (v) => setState(() => _biometricAuthEnabled = v),
                  icon: Icons.fingerprint,
                ),
                _buildActionTile(
                  title: 'Сменить пароль',
                  subtitle: 'Обновить пароль для входа',
                  icon: Icons.lock,
                  onTap: _changePassword,
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Данные и память',
              icon: Icons.storage,
              children: [
                _buildSwitchSetting(
                  title: 'Экономия трафика',
                  subtitle: 'Сжимать изображения и данные',
                  value: _dataSavingMode,
                  onChanged: (v) => setState(() => _dataSavingMode = v),
                  icon: Icons.data_saver_off,
                ),
                _buildActionTile(
                  title: 'Очистить кэш',
                  subtitle: 'Освободить место на устройстве',
                  icon: Icons.cleaning_services,
                  onTap: () {
                    // TODO: Реализовать очистку кэша
                    context.showSnackBar('Функция в разработке');
                  },
                ),
                _buildActionTile(
                  title: 'Экспорт данных',
                  subtitle: 'Скачать все ваши данные',
                  icon: Icons.download,
                  onTap: () {
                    // TODO: Реализовать экспорт данных
                    context.showSnackBar('Функция в разработке');
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Поддержка',
              icon: Icons.support,
              children: [
                _buildActionTile(
                  title: 'Связаться с поддержкой',
                  subtitle: 'Напишите нам, если возникли проблемы',
                  icon: Icons.mail,
                  onTap: _contactSupport,
                ),
                _buildActionTile(
                  title: 'Часто задаваемые вопросы',
                  subtitle: 'Ответы на популярные вопросы',
                  icon: Icons.help,
                  onTap: () {
                    // TODO: Реализовать FAQ
                    context.showSnackBar('Функция в разработке');
                  },
                ),
                _buildActionTile(
                  title: 'Сообщить об ошибке',
                  subtitle: 'Нашли ошибку? Сообщите нам!',
                  icon: Icons.bug_report,
                  onTap: () {
                    // TODO: Реализовать отчет об ошибке
                    context.showSnackBar('Функция в разработке');
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildAboutSection(),

            const SizedBox(height: 24),

            _buildActionTile(
              title: 'Выйти из аккаунта',
              subtitle: '',
              icon: Icons.logout,
              onTap: _logout,
              destructive: true,
            ),

            if (_profile?['role'] == 'admin') ...[
              const SizedBox(height: 16),
              _buildActionTile(
                title: 'Удалить аккаунт',
                subtitle: 'Это действие нельзя отменить',
                icon: Icons.delete_forever,
                onTap: _deleteAccount,
                destructive: true,
              ),
            ],

            const SizedBox(height: 32),
            Center(
              child: Text(
                '© ${DateTime.now().year} BOLASHAQ College App • Версия ${_packageInfo?.version ?? '1.0.0'}',
                style: AppTypography.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordModal extends StatefulWidget {
  const _ChangePasswordModal();

  @override
  State<_ChangePasswordModal> createState() => __ChangePasswordModalState();
}

class __ChangePasswordModalState extends State<_ChangePasswordModal> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.updateUser(UserAttributes(
        password: _newPasswordController.text,
      ));

      if (!mounted) return;

      Navigator.pop(context);
      context.showSnackBar('Пароль успешно изменен');
    } on AuthException catch (e) {
      context.showSnackBar('Ошибка: ${e.message}', isError: true);
    } catch (e) {
      context.showSnackBar('Ошибка изменения пароля', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Form(
        key: _formKey,
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
                children: [
                  Text('Смена пароля', style: AppTypography.titleLarge),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _oldPasswordController,
                    obscureText: _obscureOldPassword,
                    decoration: InputDecoration(
                      labelText: 'Текущий пароль',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureOldPassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _obscureOldPassword = !_obscureOldPassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите текущий пароль';
                      }
                      if (value.length < 6) {
                        return 'Пароль должен содержать минимум 6 символов';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: _obscureNewPassword,
                    decoration: InputDecoration(
                      labelText: 'Новый пароль',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _obscureNewPassword = !_obscureNewPassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите новый пароль';
                      }
                      if (value.length < 8) {
                        return 'Пароль должен содержать минимум 8 символов';
                      }
                      if (!value.contains(RegExp(r'[A-Z]'))) {
                        return 'Добавьте хотя бы одну заглавную букву';
                      }
                      if (!value.contains(RegExp(r'[0-9]'))) {
                        return 'Добавьте хотя бы одну цифру';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Подтвердите пароль',
                      prefixIcon: const Icon(Icons.lock_reset),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value != _newPasswordController.text) {
                        return 'Пароли не совпадают';
                      }
                      return null;
                    },
                  ),
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
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrimaryButton(
                          label: 'Сменить пароль',
                          onPressed: _isLoading ? null : () => _changePassword(),
                          isLoading: _isLoading,
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
      ),
    );
  }
}