import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';

class FoodPreorderScreen extends StatefulWidget {
  const FoodPreorderScreen({super.key});

  @override
  State<FoodPreorderScreen> createState() => _FoodPreorderScreenState();
}

class _FoodPreorderScreenState extends State<FoodPreorderScreen>
    with AutomaticKeepAliveClientMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Состояние
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _hasActiveTicket = true;
  String? _errorMessage;

  // Меню
  List<Map<String, dynamic>> _soups = [];
  List<Map<String, dynamic>> _mainDishes = [];
  List<Map<String, dynamic>> _salads = [];
  List<Map<String, dynamic>> _drinks = [];

  // Выбор пользователя
  String? _selectedSoupId;
  String? _selectedMainDishId;
  String? _selectedSaladId;
  String? _selectedDrinkId;

  // Предыдущий заказ
  Map<String, dynamic>? _previousOrder;
  Map<String, dynamic>? _existingOrder;

  // Дата для заказа (завтра)
  late DateTime _orderDate;
  late DateTime _orderDeadline;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _orderDate = DateTime(now.year, now.month, now.day + 1);
    _orderDeadline = DateTime(now.year, now.month, now.day, 22, 0); // До 22:00
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

      // Проверяем наличие активного талона
      await _checkActiveTicket(user.id);

      if (!_hasActiveTicket) {
        setState(() => _isLoading = false);
        return;
      }

      // Загружаем меню
      await _loadMenu();

      // Загружаем предыдущий заказ (на сегодня)
      await _loadPreviousOrder();

      // Проверяем, был ли уже сделан заказ на завтра
      await _loadExistingOrder();

    } catch (error) {
      debugPrint('Error loading data: $error');
      setState(() {
        _errorMessage = 'Не удалось загрузить меню';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkActiveTicket(String userId) async {
    try {
      final now = DateTime.now();
      final activeTicket = await _supabase
          .from('tickets')
          .select('*')
          .eq('student_id', userId)
          .eq('is_active', true)
          .gte('end_date', now.toIso8601String())
          .maybeSingle();

      setState(() => _hasActiveTicket = activeTicket != null);
    } catch (error) {
      debugPrint('Error checking active ticket: $error');
    }
  }

  // Обновите метод _loadMenu():
  Future<void> _loadMenu() async {
    try {
      final tomorrow = _getFormattedDate(_orderDate);

      // Используйте функцию get_daily_menu или запрос напрямую
      final menuResponse = await _supabase
          .from('daily_menu')
          .select('''
          *,
          menu_items!soup_ids(*),
          menu_items!main_dish_ids(*),
          menu_items!salad_ids(*),
          menu_items!drink_ids(*)
        ''')
          .eq('menu_date', tomorrow)
          .eq('meal_type', 'lunch')
          .maybeSingle();

      if (menuResponse == null) {
        // Если нет меню на завтра, загружаем все активные блюда
        await _loadDefaultMenu();
        return;
      }

      // Разделяем блюда по категориям
      setState(() {
        _soups = List<Map<String, dynamic>>.from(menuResponse['soup_ids'] ?? []);
        _mainDishes = List<Map<String, dynamic>>.from(menuResponse['main_dish_ids'] ?? []);
        _salads = List<Map<String, dynamic>>.from(menuResponse['salad_ids'] ?? []);
        _drinks = List<Map<String, dynamic>>.from(menuResponse['drink_ids'] ?? []);
      });
    } catch (error) {
      debugPrint('Error loading menu: $error');
      await _loadDefaultMenu();
    }
  }

  Future<void> _loadDefaultMenu() async {
    try {
      final menuItems = await _supabase
          .from('menu_items')
          .select('*')
          .eq('is_active', true);

      setState(() {
        _soups = menuItems.where((item) => item['category'] == 'soup').toList();
        _mainDishes = menuItems.where((item) => item['category'] == 'main').toList();
        _salads = menuItems.where((item) => item['category'] == 'salad').toList();
        _drinks = menuItems.where((item) => item['category'] == 'drink').toList();
      });
    } catch (error) {
      debugPrint('Error loading default menu: $error');
    }
  }

  Future<void> _loadPreviousOrder() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final today = DateTime.now();
      final previousOrder = await _supabase
          .from('food_orders')
          .select('''
            *,
            menu_items!soup_id(title),
            menu_items!main_dish_id(title),
            menu_items!salad_id(title),
            menu_items!drink_id(title)
          ''')
          .eq('student_id', user.id)
          .eq('order_date', _getFormattedDate(today))
          .maybeSingle();

      if (previousOrder != null) {
        setState(() => _previousOrder = previousOrder);
      }
    } catch (error) {
      debugPrint('Error loading previous order: $error');
    }
  }

  Future<void> _loadExistingOrder() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final existingOrder = await _supabase
          .from('food_orders')
          .select('*')
          .eq('student_id', user.id)
          .eq('order_date', _getFormattedDate(_orderDate))
          .maybeSingle();

      if (existingOrder != null) {
        setState(() {
          _existingOrder = existingOrder;
          _selectedSoupId = existingOrder['soup_id'];
          _selectedMainDishId = existingOrder['main_dish_id'];
          _selectedSaladId = existingOrder['salad_id'];
          _selectedDrinkId = existingOrder['drink_id'];
        });
      }
    } catch (error) {
      debugPrint('Error loading existing order: $error');
    }
  }

  Future<void> _submitOrder() async {
    if (_selectedSoupId == null || _selectedMainDishId == null) {
      _showSnackBar('Выберите хотя бы суп и основное блюдо', isError: true);
      return;
    }

    final now = DateTime.now();
    if (now.isAfter(_orderDeadline)) {
      _showSnackBar('Прием заказов на завтра завершен (до 22:00)', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        _redirectToLogin();
        return;
      }

      final orderData = {
        'student_id': user.id,
        'order_date': _getFormattedDate(_orderDate),
        'soup_id': _selectedSoupId,
        'main_dish_id': _selectedMainDishId,
        'salad_id': _selectedSaladId,
        'drink_id': _selectedDrinkId,
        'ordered_at': DateTime.now().toIso8601String(),
        'status': 'pending',
      };

      if (_existingOrder != null) {
        // Обновляем существующий заказ
        await _supabase
            .from('food_orders')
            .update(orderData)
            .eq('id', _existingOrder!['id']);
        _showSnackBar('Заказ обновлен!');
      } else {
        // Создаем новый заказ
        await _supabase.from('food_orders').insert(orderData);
        _showSnackBar('Заказ оформлен!');
      }

      // Обновляем существующий заказ
      await _loadExistingOrder();

    } catch (error) {
      debugPrint('Error submitting order: $error');
      _showSnackBar('Ошибка при оформлении заказа: $error', isError: true);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/login');
    });
  }

  String _getFormattedDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildNoTicketMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'Нет активного талона',
              style: AppTypography.titleMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Для заказа еды необходим активный талон питания',
              style: AppTypography.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushNamed('/coupons');
              },
              child: const Text('Перейти к талонам'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviousOrder() {
    if (_previousOrder == null) return const SizedBox.shrink();

    final soupTitle = _previousOrder!['menu_items']?[0]['title'] ?? 'Не выбран';
    final mainDishTitle = _previousOrder!['menu_items']?[1]['title'] ?? 'Не выбран';
    final saladTitle = _previousOrder!['menu_items']?[2]['title'] ?? 'Не выбран';
    final drinkTitle = _previousOrder!['menu_items']?[3]['title'] ?? 'Не выбран';

    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Ваш заказ на сегодня',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (soupTitle != 'Не выбран') _buildOrderItem('Суп', soupTitle),
          if (mainDishTitle != 'Не выбран') _buildOrderItem('Основное', mainDishTitle),
          if (saladTitle != 'Не выбран') _buildOrderItem('Салат', saladTitle),
          if (drinkTitle != 'Не выбран') _buildOrderItem('Напиток', drinkTitle),
        ],
      ),
    );
  }

  Widget _buildOrderItem(String category, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$category:',
              style: AppTypography.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDishSelection(
      String title,
      String? selectedId,
      List<Map<String, dynamic>> dishes,
      bool isRequired,
      Function(String?) onChanged,
      ) {
    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isRequired)
                const Text(
                  ' *',
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (dishes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Нет доступных вариантов',
                style: AppTypography.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            )
          else
            Column(
              children: dishes.map((dish) {
                final isSelected = selectedId == dish['id'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {
                        if (isSelected && !isRequired) {
                          onChanged(null);
                        } else {
                          onChanged(dish['id']);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.grey.shade300,
                                  width: 2,
                                ),
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                              ),
                              child: isSelected
                                  ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dish['title'],
                                    style: AppTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (dish['description'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        dish['description'],
                                        style: AppTypography.bodySmall.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.6),
                                        ),
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
                );
              }).toList(),
            ),

          if (!isRequired && selectedId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => onChanged(null),
                  child: const Text('Убрать выбор'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    final now = DateTime.now();
    final isAfterDeadline = now.isAfter(_orderDeadline);
    final remainingTime = _orderDeadline.difference(now);

    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: isAfterDeadline ? AppColors.error : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isAfterDeadline ? 'Прием заказов завершен' : 'Как это работает:',
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isAfterDeadline
                ? 'Заказы на завтра принимаются до 22:00. Закажите завтра утром.'
                : 'Выберите блюда на завтра. Заказ будет доступен в столовой с 12:00 до 14:00.',
            style: AppTypography.bodySmall,
          ),
          if (!isAfterDeadline) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Осталось: ${remainingTime.inHours}ч ${remainingTime.inMinutes.remainder(60)}м',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Предзаказ еды'),
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
            Text(
              _errorMessage!,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Повторить'),
            ),
          ],
        ),
      )
          : !_hasActiveTicket
          ? _buildNoTicketMessage()
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Дата заказа
            ModernCard(
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Заказ на завтра',
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          DateFormat('dd MMMM yyyy', 'ru_RU').format(_orderDate),
                          style: AppTypography.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  if (_existingOrder != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Text(
                        'Заказано',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Предыдущий заказ
            if (_previousOrder != null) ...[
              _buildPreviousOrder(),
              const SizedBox(height: 20),
            ],

            // Выбор блюд
            _buildDishSelection(
              'Суп',
              _selectedSoupId,
              _soups,
              true,
                  (value) => setState(() => _selectedSoupId = value),
            ),

            const SizedBox(height: 16),

            _buildDishSelection(
              'Основное блюдо',
              _selectedMainDishId,
              _mainDishes,
              true,
                  (value) => setState(() => _selectedMainDishId = value),
            ),

            const SizedBox(height: 16),

            _buildDishSelection(
              'Салат',
              _selectedSaladId,
              _salads,
              false,
                  (value) => setState(() => _selectedSaladId = value),
            ),

            const SizedBox(height: 16),

            _buildDishSelection(
              'Напиток',
              _selectedDrinkId,
              _drinks,
              false,
                  (value) => setState(() => _selectedDrinkId = value),
            ),

            const SizedBox(height: 20),

            // Инструкции
            _buildInstructions(),

            const SizedBox(height: 32),

            // Кнопка отправки
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting
                    ? null
                    : DateTime.now().isAfter(_orderDeadline)
                    ? null
                    : _submitOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DateTime.now().isAfter(_orderDeadline)
                      ? Colors.grey
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      DateTime.now().isAfter(_orderDeadline)
                          ? Icons.schedule
                          : _existingOrder != null
                          ? Icons.edit
                          : Icons.restaurant_menu,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateTime.now().isAfter(_orderDeadline)
                          ? 'Прием заказов завершен'
                          : _existingOrder != null
                          ? 'Изменить заказ'
                          : 'Забронировать на завтра',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
    );
  }
}

// ModernCard виджет
class ModernCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ModernCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}