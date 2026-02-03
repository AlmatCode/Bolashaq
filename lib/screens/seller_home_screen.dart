// lib/screens/seller_home_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'qr_redeem_screen.dart';
import 'food_preorder_screen.dart';
import '../core/theme.dart';

class SellerHomeScreen extends StatefulWidget {
  const SellerHomeScreen({super.key});

  @override
  State<SellerHomeScreen> createState() => _SellerHomeScreenState();
}

class _SellerHomeScreenState extends State<SellerHomeScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  late TabController _tabController;

  // Для вкладки "Управление меню"
  DateTime _selectedDate = DateTime.now();
  bool _isLoadingOrders = true;
  List<FoodOrder> _orders = [];
  String _selectedStatusFilter = 'all';
  List<String> _statusFilters = ['all', 'pending', 'completed', 'cancelled'];
  Map<String, int> _orderStats = {
    'total': 0,
    'pending': 0,
    'completed': 0,
    'cancelled': 0,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);

    // Загружаем заказы при инициализации
    if (mounted) {
      _loadOrdersForDate(_selectedDate);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.index == 1) {
      // При переходе на вкладку управления меню обновляем данные
      _loadOrdersForDate(_selectedDate);
    }
  }

  Future<void> _logout() async {
    try {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка выхода: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showLogoutDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _logout();
    }
  }

  Future<void> _loadOrdersForDate(DateTime date) async {
    if (!mounted) return;

    setState(() {
      _isLoadingOrders = true;
      _orders = [];
      _orderStats = {'total': 0, 'pending': 0, 'completed': 0, 'cancelled': 0};
    });

    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);

      // Получаем все заказы на выбранную дату
      final response = await _supabase
          .from('food_orders')
          .select('''
            *,
            profiles:student_id(full_name, email, student_group),
            soup:menu_items!soup_id(title, category),
            main_dish:menu_items!main_dish_id(title, category),
            salad:menu_items!salad_id(title, category),
            drink:menu_items!drink_id(title, category)
          ''')
          .eq('order_date', formattedDate)
          .order('ordered_at', ascending: false);

      if (response is List && response.isNotEmpty) {
        List<FoodOrder> loadedOrders = [];
        Map<String, int> stats = {'total': 0, 'pending': 0, 'completed': 0, 'cancelled': 0};

        for (var orderData in response) {
          try {
            final order = FoodOrder.fromJson(Map<String, dynamic>.from(orderData));
            loadedOrders.add(order);

            // Обновляем статистику
            stats['total'] = (stats['total'] ?? 0) + 1;
            stats[order.status] = (stats[order.status] ?? 0) + 1;
          } catch (e) {
            debugPrint('Error parsing order: $e');
          }
        }

        if (mounted) {
          setState(() {
            _orders = loadedOrders;
            _orderStats = stats;
            _isLoadingOrders = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingOrders = false;
          });
        }
      }
    } catch (error) {
      debugPrint('Error loading orders: $error');
      if (mounted) {
        setState(() {
          _isLoadingOrders = false;
        });
        _showErrorSnackBar('Не удалось загрузить заказы');
      }
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      setState(() {
        // Оптимистичное обновление UI
        _orders = _orders.map((order) {
          if (order.id == orderId) {
            final oldStatus = order.status;
            final updatedOrder = order.copyWith(status: newStatus);

            // Обновляем статистику
            _orderStats[oldStatus] = (_orderStats[oldStatus] ?? 1) - 1;
            _orderStats[newStatus] = (_orderStats[newStatus] ?? 0) + 1;

            return updatedOrder;
          }
          return order;
        }).toList();
      });

      // Обновляем в базе данных
      await _supabase
          .from('food_orders')
          .update({
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
        'completed_at': newStatus == 'completed'
            ? DateTime.now().toIso8601String()
            : null,
      })
          .eq('id', orderId);

      _showSuccessSnackBar('Статус заказа обновлен');
    } catch (error) {
      debugPrint('Error updating order: $error');

      // Откатываем изменения в UI
      _loadOrdersForDate(_selectedDate);
      _showErrorSnackBar('Не удалось обновить статус');
    }
  }

  Future<void> _showOrderDetails(FoodOrder order) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Детали заказа #${order.shortId}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Студент:', order.studentName),
              _buildDetailRow('Группа:', order.studentGroup),
              _buildDetailRow('Email:', order.studentEmail),
              const SizedBox(height: 16),
              Text('Заказанные блюда:', style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              )),
              const SizedBox(height: 8),
              if (order.soupTitle != null)
                _buildOrderItem('Суп', order.soupTitle!),
              if (order.mainDishTitle != null)
                _buildOrderItem('Основное', order.mainDishTitle!),
              if (order.saladTitle != null)
                _buildOrderItem('Салат', order.saladTitle!),
              if (order.drinkTitle != null)
                _buildOrderItem('Напиток', order.drinkTitle!),
              const SizedBox(height: 16),
              _buildDetailRow('Дата заказа:', DateFormat('dd.MM.yyyy HH:mm').format(order.orderedAt)),
              _buildDetailRow('Статус:', _getStatusLabel(order.status)),
              if (order.completedAt != null)
                _buildDetailRow('Выдан:', DateFormat('dd.MM.yyyy HH:mm').format(order.completedAt!)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
          if (order.status == 'pending')
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateOrderStatus(order.id, 'completed');
              },
              child: const Text('Отметить выданным'),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(String category, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$category:',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'Ожидает';
      case 'completed': return 'Выдан';
      case 'cancelled': return 'Отменен';
      default: return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'completed': return AppColors.success;
      case 'cancelled': return AppColors.error;
      default: return Colors.grey;
    }
  }

  Widget _buildDateSelector() {
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedDate = today;
                });
                _loadOrdersForDate(today);
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: _selectedDate.day == today.day
                    ? AppColors.primary.withOpacity(0.1)
                    : null,
                side: BorderSide(
                  color: _selectedDate.day == today.day
                      ? AppColors.primary
                      : Theme.of(context).dividerColor,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Сегодня',
                    style: TextStyle(
                      fontWeight: _selectedDate.day == today.day
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _selectedDate.day == today.day
                          ? AppColors.primary
                          : null,
                    ),
                  ),
                  Text(
                    DateFormat('dd.MM').format(today),
                    style: TextStyle(
                      fontSize: 12,
                      color: _selectedDate.day == today.day
                          ? AppColors.primary
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedDate = tomorrow;
                });
                _loadOrdersForDate(tomorrow);
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: _selectedDate.day == tomorrow.day
                    ? AppColors.primary.withOpacity(0.1)
                    : null,
                side: BorderSide(
                  color: _selectedDate.day == tomorrow.day
                      ? AppColors.primary
                      : Theme.of(context).dividerColor,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Завтра',
                    style: TextStyle(
                      fontWeight: _selectedDate.day == tomorrow.day
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _selectedDate.day == tomorrow.day
                          ? AppColors.primary
                          : null,
                    ),
                  ),
                  Text(
                    DateFormat('dd.MM').format(tomorrow),
                    style: TextStyle(
                      fontSize: 12,
                      color: _selectedDate.day == tomorrow.day
                          ? AppColors.primary
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Всего', _orderStats['total']?.toString() ?? '0', AppColors.primary),
          _buildStatItem('Ожидают', _orderStats['pending']?.toString() ?? '0', Colors.orange),
          _buildStatItem('Выдано', _orderStats['completed']?.toString() ?? '0', AppColors.success),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(FoodOrder order) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => _showOrderDetails(order),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.studentName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        if (order.studentGroup.isNotEmpty)
                          Text(
                            order.studentGroup,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(order.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getStatusColor(order.status).withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      _getStatusLabel(order.status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(order.status),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Список блюд
              if (order.soupTitle != null || order.mainDishTitle != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (order.soupTitle != null)
                      _buildDishChip('Суп', order.soupTitle!),
                    if (order.mainDishTitle != null)
                      _buildDishChip('Основное', order.mainDishTitle!),
                    if (order.saladTitle != null)
                      _buildDishChip('Салат', order.saladTitle!),
                    if (order.drinkTitle != null)
                      _buildDishChip('Напиток', order.drinkTitle!),
                  ],
                ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('HH:mm').format(order.orderedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),

                  if (order.status == 'pending')
                    ElevatedButton(
                      onPressed: () => _updateOrderStatus(order.id, 'completed'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Выдать'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDishChip(String category, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$category: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _statusFilters.map((status) {
          final isSelected = _selectedStatusFilter == status;
          final label = status == 'all' ? 'Все' : _getStatusLabel(status);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedStatusFilter = selected ? status : 'all';
                });
              },
              backgroundColor: isSelected
                  ? AppColors.primary.withOpacity(0.1)
                  : Theme.of(context).colorScheme.surfaceVariant,
              selectedColor: AppColors.primary.withOpacity(0.2),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? AppColors.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? AppColors.primary
                      : Theme.of(context).dividerColor,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrdersList() {
    if (_isLoadingOrders) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant_menu_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Нет заказов на выбранную дату',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Заказы появятся здесь, когда студенты\nсделают предзаказ еды',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    // Фильтруем заказы по статусу
    List<FoodOrder> filteredOrders = _orders;
    if (_selectedStatusFilter != 'all') {
      filteredOrders = _orders.where((order) => order.status == _selectedStatusFilter).toList();
    }

    return RefreshIndicator(
      onRefresh: () => _loadOrdersForDate(_selectedDate),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: filteredOrders.length,
        itemBuilder: (context, index) {
          return _buildOrderCard(filteredOrders[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Панель продавца'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _showLogoutDialog,
            tooltip: 'Выйти',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.qr_code_scanner),
              text: 'Сканирование QR',
            ),
            Tab(
              icon: Icon(Icons.restaurant_menu),
              text: 'Управление меню',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Вкладка 1: Сканирование QR
          const QrRedeemScreen(),

          // Вкладка 2: Управление меню
          Column(
            children: [
              // Выбор даты
              _buildDateSelector(),

              // Статистика
              _buildStatistics(),

              // Фильтры по статусу
              _buildFilterChips(),

              // Список заказов
              Expanded(
                child: _buildOrdersList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Модель заказа еды
class FoodOrder {
  final String id;
  final String studentId;
  final String studentName;
  final String studentEmail;
  final String studentGroup;
  final DateTime orderDate;
  final String? soupId;
  final String? mainDishId;
  final String? saladId;
  final String? drinkId;
  final String? soupTitle;
  final String? mainDishTitle;
  final String? saladTitle;
  final String? drinkTitle;
  final String status;
  final DateTime orderedAt;
  final DateTime? completedAt;

  FoodOrder({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.studentGroup,
    required this.orderDate,
    this.soupId,
    this.mainDishId,
    this.saladId,
    this.drinkId,
    this.soupTitle,
    this.mainDishTitle,
    this.saladTitle,
    this.drinkTitle,
    required this.status,
    required this.orderedAt,
    this.completedAt,
  });

  factory FoodOrder.fromJson(Map<String, dynamic> json) {
    return FoodOrder(
      id: json['id']?.toString() ?? '',
      studentId: json['student_id']?.toString() ?? '',
      studentName: (json['profiles'] is Map
          ? Map<String, dynamic>.from(json['profiles'])
          : {})['full_name']?.toString() ?? 'Неизвестный',
      studentEmail: (json['profiles'] is Map
          ? Map<String, dynamic>.from(json['profiles'])
          : {})['email']?.toString() ?? '',
      studentGroup: (json['profiles'] is Map
          ? Map<String, dynamic>.from(json['profiles'])
          : {})['student_group']?.toString() ?? '',
      orderDate: json['order_date'] != null
          ? DateFormat('yyyy-MM-dd').parse(json['order_date'].toString())
          : DateTime.now(),
      soupId: json['soup_id']?.toString(),
      mainDishId: json['main_dish_id']?.toString(),
      saladId: json['salad_id']?.toString(),
      drinkId: json['drink_id']?.toString(),
      soupTitle: (json['soup'] is Map
          ? Map<String, dynamic>.from(json['soup'])
          : {})['title']?.toString(),
      mainDishTitle: (json['main_dish'] is Map
          ? Map<String, dynamic>.from(json['main_dish'])
          : {})['title']?.toString(),
      saladTitle: (json['salad'] is Map
          ? Map<String, dynamic>.from(json['salad'])
          : {})['title']?.toString(),
      drinkTitle: (json['drink'] is Map
          ? Map<String, dynamic>.from(json['drink'])
          : {})['title']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      orderedAt: json['ordered_at'] != null
          ? DateTime.parse(json['ordered_at'].toString())
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'].toString())
          : null,
    );
  }

  FoodOrder copyWith({
    String? id,
    String? studentId,
    String? studentName,
    String? studentEmail,
    String? studentGroup,
    DateTime? orderDate,
    String? soupId,
    String? mainDishId,
    String? saladId,
    String? drinkId,
    String? soupTitle,
    String? mainDishTitle,
    String? saladTitle,
    String? drinkTitle,
    String? status,
    DateTime? orderedAt,
    DateTime? completedAt,
  }) {
    return FoodOrder(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      studentEmail: studentEmail ?? this.studentEmail,
      studentGroup: studentGroup ?? this.studentGroup,
      orderDate: orderDate ?? this.orderDate,
      soupId: soupId ?? this.soupId,
      mainDishId: mainDishId ?? this.mainDishId,
      saladId: saladId ?? this.saladId,
      drinkId: drinkId ?? this.drinkId,
      soupTitle: soupTitle ?? this.soupTitle,
      mainDishTitle: mainDishTitle ?? this.mainDishTitle,
      saladTitle: saladTitle ?? this.saladTitle,
      drinkTitle: drinkTitle ?? this.drinkTitle,
      status: status ?? this.status,
      orderedAt: orderedAt ?? this.orderedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  String get shortId => id.length > 8 ? '${id.substring(0, 8)}...' : id;
}