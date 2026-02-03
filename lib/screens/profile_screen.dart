import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../core/theme.dart';

// Добавьте этот виджет в начало файла или в отдельный файл
class ModernCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const ModernCard({
    Key? key,
    required this.child,
    this.padding,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Состояние
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isUploading = false;
  String? _error;

  // Данные профиля
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _userSettings;
  File? _selectedAvatar;

  // Контроллеры формы
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _studentGroupController = TextEditingController();
  final TextEditingController _studentSpecialityController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _yearOfStudyController = TextEditingController();
  final TextEditingController _iinController = TextEditingController();

  // Статистика
  Map<String, dynamic> _userStats = {
    'active_tickets': 0,
    'total_tickets': 0,
    'total_used_days': 0,
    'attendance_rate': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _studentIdController.dispose();
    _bioController.dispose();
    _studentGroupController.dispose();
    _studentSpecialityController.dispose();
    _departmentController.dispose();
    _yearOfStudyController.dispose();
    _iinController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
        return;
      }

      // Загружаем профиль из таблицы profiles
      final profileResponse = await _supabase
          .from('profiles')
          .select('''
            id, 
            full_name, 
            email, 
            phone, 
            student_id, 
            iin,
            category,
            role, 
            student_group, 
            student_speciality,
            department, 
            year_of_study, 
            verified_for_food, 
            balance, 
            avatar_url, 
            bio,
            additional_data,
            last_login,
            created_at, 
            updated_at
          ''')
          .eq('id', user.id)
          .single();

      _profile = Map<String, dynamic>.from(profileResponse);

      // Загружаем настройки пользователя
      try {
        final settingsResponse = await _supabase
            .from('user_settings')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();

        if (settingsResponse != null) {
          _userSettings = Map<String, dynamic>.from(settingsResponse);
        }
      } catch (e) {
        debugPrint('Ошибка загрузки настроек: $e');
      }

      // Заполняем контроллеры
      _fullNameController.text = _profile?['full_name']?.toString() ?? '';
      _phoneController.text = _profile?['phone']?.toString() ?? '';
      _studentIdController.text = _profile?['student_id']?.toString() ?? '';
      _bioController.text = _profile?['bio']?.toString() ?? '';
      _studentGroupController.text = _profile?['student_group']?.toString() ?? '';
      _studentSpecialityController.text = _profile?['student_speciality']?.toString() ?? '';
      _departmentController.text = _profile?['department']?.toString() ?? '';
      _yearOfStudyController.text = _profile?['year_of_study']?.toString() ?? '';
      _iinController.text = _profile?['iin']?.toString() ?? '';

      // Загружаем статистику
      await _loadUserStatistics(user.id);

    } on PostgrestException catch (e) {
      setState(() {
        _error = 'Ошибка базы данных: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки профиля: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUserStatistics(String userId) async {
    try {
      // Загружаем все талоны пользователя
      final ticketsResponse = await _supabase
          .from('tickets')
          .select('total_days, used_days, is_active')
          .eq('student_id', userId);

      int totalDays = 0;
      int usedDays = 0;
      int activeTickets = 0;

      for (var ticket in ticketsResponse) {
        totalDays += (ticket['total_days'] as int? ?? 0);
        usedDays += (ticket['used_days'] as int? ?? 0);
        if (ticket['is_active'] == true) {
          activeTickets++;
        }
      }

      // Рассчитываем процент посещаемости
      int attendanceRate = totalDays > 0 ? ((usedDays / totalDays) * 100).round() : 0;

      setState(() {
        _userStats = {
          'active_tickets': activeTickets,
          'total_tickets': ticketsResponse.length,
          'total_used_days': usedDays,
          'attendance_rate': attendanceRate,
        };
      });
    } catch (e) {
      debugPrint('Ошибка загрузки статистики: $e');
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Не авторизован');

      // Загружаем аватар в storage, если выбран
      String? avatarUrl;
      if (_selectedAvatar != null) {
        String fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          await _supabase.storage.from('avatars').upload(fileName, _selectedAvatar!);
        } catch (e) {
          throw Exception('Ошибка загрузки аватара: $e');
        }

        // Получаем публичный URL
        avatarUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      }

      // Подготавливаем данные для обновления
      final Map<String, dynamic> updateData = {
        'full_name': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'student_id': _studentIdController.text.trim(),
        'student_group': _studentGroupController.text.trim(),
        'student_speciality': _studentSpecialityController.text.trim(),
        'department': _departmentController.text.trim(),
        'bio': _bioController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Добавляем год обучения, если он числовой
      final yearOfStudy = int.tryParse(_yearOfStudyController.text.trim());
      if (yearOfStudy != null) {
        updateData['year_of_study'] = yearOfStudy;
      }

      // Добавляем ИИН
      if (_iinController.text.trim().isNotEmpty) {
        updateData['iin'] = _iinController.text.trim();
      }

      // Добавляем URL аватара, если загружен
      if (avatarUrl != null) {
        updateData['avatar_url'] = avatarUrl;
      }

      // Обновляем профиль в базе данных
      final response = await _supabase
          .from('profiles')
          .update(updateData)
          .eq('id', user.id);

      if (response.error != null) {
        throw Exception('Ошибка обновления профиля: ${response.error!.message}');
      }

      // Обновляем локальные данные
      await _loadProfileData();

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Профиль успешно обновлен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка обновления: ${e.toString()}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления профиля: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _selectedAvatar = File(pickedFile.path);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ошибка выбора изображения'),
            backgroundColor: Colors.red,
          ),
        );
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
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выхода: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareProfile() async {
    try {
      final profileText = '''
👤 ${_profile?['full_name'] ?? 'Не указано'}
🎓 ID студента: ${_profile?['student_id'] ?? 'Не указано'}
📧 Email: ${_profile?['email'] ?? 'Не указано'}
📱 Телефон: ${_profile?['phone'] ?? 'Не указано'}
🏫 Группа: ${_profile?['student_group'] ?? 'Не указано'}
🎯 Специальность: ${_profile?['student_speciality'] ?? 'Не указано'}
🏛️ Отдел: ${_profile?['department'] ?? 'Не указано'}
📅 Год обучения: ${_profile?['year_of_study'] ?? 'Не указано'}
💼 Роль: ${_getRoleText(_profile?['role'])}
✅ Верификация: ${_profile?['verified_for_food'] == true ? 'Подтвержден' : 'Не подтвержден'}
💰 Баланс: ${double.tryParse(_profile?['balance']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'} ₽
📊 Посещаемость: ${_userStats['attendance_rate']}%
''';

      await Share.share(
        profileText,
        subject: 'Профиль пользователя ${_profile?['full_name']}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ошибка при попытке поделиться'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getRoleText(String? role) {
    switch (role) {
      case 'admin':
        return 'Администратор';
      case 'teacher':
        return 'Преподаватель';
      case 'seller':
        return 'Продавец';
      case 'staff':
        return 'Персонал';
      default:
        return 'Студент';
    }
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Widget _buildAvatar() {
    final hasSelectedAvatar = _selectedAvatar != null;
    final hasProfileAvatar = (_profile?['avatar_url'] as String?)?.isNotEmpty == true;

    Widget avatarWidget;

    if (hasSelectedAvatar) {
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(60),
        child: Image.file(
          _selectedAvatar!,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        ),
      );
    } else if (hasProfileAvatar) {
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(60),
        child: Image.network(
          _profile!['avatar_url'] as String,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar();
          },
        ),
      );
    } else {
      avatarWidget = _buildDefaultAvatar();
    }

    return Stack(
      children: [
        Container(
          width: 124,
          height: 124,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: avatarWidget,
            ),
          ),
        ),
        if (_isEditing)
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _getInitials(_profile?['full_name']?.toString()),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return ModernCard(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                icon: Icons.confirmation_number,
                value: _userStats['active_tickets'].toString(),
                label: 'Активные талоны',
                color: Colors.blue,
              ),
              _buildStatItem(
                icon: Icons.assignment,
                value: _userStats['total_tickets'].toString(),
                label: 'Всего талонов',
                color: Colors.green,
              ),
              _buildStatItem(
                icon: Icons.check_circle,
                value: '${_userStats['attendance_rate']}%',
                label: 'Посещаемость',
                color: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatItem(
                icon: Icons.calendar_today,
                value: _userStats['total_used_days'].toString(),
                label: 'Использовано дней',
                color: Colors.purple,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Icon(icon, size: 24, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge() {
    final role = _profile?['role']?.toString() ?? 'student';
    final verified = _profile?['verified_for_food'] == true;
    final category = _profile?['category']?.toString();

    Color roleColor;
    String roleText;

    switch (role) {
      case 'admin':
        roleColor = Colors.red;
        roleText = 'Администратор';
        break;
      case 'teacher':
        roleColor = Colors.blue;
        roleText = 'Преподаватель';
        break;
      case 'seller':
        roleColor = Colors.green;
        roleText = 'Продавец';
        break;
      case 'staff':
        roleColor = Colors.orange;
        roleText = 'Персонал';
        break;
      default:
        roleColor = Theme.of(context).colorScheme.primary;
        roleText = 'Студент';
    }

    // Цвета для категорий
    Color getCategoryColor(String? cat) {
      switch (cat) {
        case 'Free Payer':
          return Colors.green;
        case 'Payer':
          return Colors.blue;
        case 'Grant Payer':
          return Colors.purple;
        case 'Staff':
          return Colors.orange;
        default:
          return Colors.grey;
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        // Бейдж роли
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: roleColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                role == 'admin' ? Icons.admin_panel_settings :
                role == 'teacher' ? Icons.school :
                role == 'seller' ? Icons.shopping_cart :
                role == 'staff' ? Icons.work : Icons.school,
                size: 14,
                color: roleColor,
              ),
              const SizedBox(width: 6),
              Text(
                roleText,
                style: TextStyle(
                  fontSize: 12,
                  color: roleColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Бейдж категории
        if (category != null && category.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: getCategoryColor(category).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.category,
                  size: 14,
                  color: getCategoryColor(category),
                ),
                const SizedBox(width: 6),
                Text(
                  category,
                  style: TextStyle(
                    fontSize: 12,
                    color: getCategoryColor(category),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        // Бейдж верификации
        if (verified)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified, size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Text(
                  'Верифицирован',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          const SizedBox(height: 16),
          TextFormField(
            controller: _fullNameController,
            decoration: const InputDecoration(
              labelText: 'Полное имя *',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Введите ваше имя';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _iinController,
            decoration: const InputDecoration(
              labelText: 'ИИН',
              prefixIcon: Icon(Icons.fingerprint),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            maxLength: 12,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _studentIdController,
            decoration: const InputDecoration(
              labelText: 'Номер студенческого билета',
              prefixIcon: Icon(Icons.badge),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Телефон',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _studentGroupController,
            decoration: const InputDecoration(
              labelText: 'Группа',
              prefixIcon: Icon(Icons.group),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _studentSpecialityController,
            decoration: const InputDecoration(
              labelText: 'Специальность',
              prefixIcon: Icon(Icons.school),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _departmentController,
            decoration: const InputDecoration(
              labelText: 'Отдел/Факультет',
              prefixIcon: Icon(Icons.business),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _yearOfStudyController,
            decoration: const InputDecoration(
              labelText: 'Год обучения',
              prefixIcon: Icon(Icons.calendar_today),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _bioController,
            decoration: const InputDecoration(
              labelText: 'О себе',
              prefixIcon: Icon(Icons.info),
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
            maxLength: 200,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfoCard() {
    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoRow(
            icon: Icons.fingerprint,
            label: 'ИИН',
            value: _profile?['iin']?.toString() ?? 'Не указано',
            color: Colors.blue,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.badge,
            label: 'ID студента',
            value: _profile?['student_id']?.toString() ?? 'Не указано',
            color: Colors.green,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.group,
            label: 'Группа',
            value: _profile?['student_group']?.toString() ?? 'Не указано',
            color: Colors.purple,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.school,
            label: 'Специальность',
            value: _profile?['student_speciality']?.toString() ?? 'Не указано',
            color: Colors.orange,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.business,
            label: 'Отдел/Факультет',
            value: _profile?['department']?.toString() ?? 'Не указано',
            color: Colors.red,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.calendar_today,
            label: 'Год обучения',
            value: _profile?['year_of_study']?.toString() ?? 'Не указано',
            color: Colors.teal,
          ),
          if (_profile?['bio'] != null && (_profile?['bio'] as String).isNotEmpty) ...[
            _buildDivider(),
            _buildInfoRow(
              icon: Icons.info,
              label: 'О себе',
              value: _profile?['bio']?.toString() ?? '',
              color: Colors.indigo,
              multiLine: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool multiLine = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: multiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: multiLine ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 20,
      thickness: 1,
      color: Theme.of(context).dividerColor.withOpacity(0.1),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isUploading
                  ? null
                  : _isEditing
                  ? () {
                if (_formKey.currentState!.validate()) {
                  _updateProfile();
                }
              }
                  : () => setState(() => _isEditing = true),
              icon: Icon(
                _isEditing ? Icons.save : Icons.edit,
                size: 20,
              ),
              label: Text(_isEditing ? 'Сохранить изменения' : 'Редактировать профиль'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _shareProfile,
              icon: const Icon(Icons.share, size: 20),
              label: const Text('Поделиться'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    final balance = double.tryParse(_profile?['balance']?.toString() ?? '0') ?? 0.0;

    return ModernCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Баланс',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$balance ₸',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              // Навигация к пополнению баланса
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Функция пополнения баланса в разработке'),
                ),
              );
            },
            child: const Text('Пополнить'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(
              Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Загрузка профиля...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
              _error ?? 'Произошла ошибка',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadProfileData,
              child: const Text('Повторить'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _logout,
              child: const Text('Выйти'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileContent() {
    return RefreshIndicator(
      onRefresh: _loadProfileData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildAvatar(),
            const SizedBox(height: 24),
            Text(
              _profile?['full_name']?.toString() ?? 'Без имени',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _profile?['email']?.toString() ?? 'Нет email',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildRoleBadge(),
            const SizedBox(height: 24),
            _buildBalanceCard(),
            const SizedBox(height: 24),
            _buildStatsCard(),
            const SizedBox(height: 24),
            if (_isEditing)
              _buildEditForm()
            else
              _buildProfileInfoCard(),
            const SizedBox(height: 24),
            _buildActionButtons(),
            const SizedBox(height: 16),
            if (_profile?['created_at'] != null)
              Text(
                'Участник с ${DateFormat('dd.MM.yyyy').format(DateTime.parse(_profile!['created_at']))}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _logout,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 8),
                  Text('Выйти из аккаунта'),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: true,
        actions: [
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _error != null
          ? _buildErrorState()
          : _buildProfileContent(),
    );
  }
}