// Замените весь файл lib/screens/qr_redeem_screen.dart:

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:clipboard/clipboard.dart';
import '../core/theme.dart';

class QrRedeemScreen extends StatefulWidget {
  const QrRedeemScreen({super.key});

  @override
  State<QrRedeemScreen> createState() => _QrRedeemScreenState();
}

class _QrRedeemScreenState extends State<QrRedeemScreen> {
  final _supabase = Supabase.instance.client;
  late MobileScannerController _scannerController;
  bool _isProcessing = false;
  bool _flashEnabled = false;
  bool _cameraFacingFront = false;
  Timer? _scanCooldownTimer;

  // Manual input
  final TextEditingController _ticketIdController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  // Results
  String? _resultMessage;
  bool? _success;
  Map<String, dynamic>? _scannedData;
  Map<String, dynamic>? _studentInfo;

  // History
  List<Map<String, dynamic>> _scanHistory = [];

  @override
  void initState() {
    super.initState();

    _scannerController = MobileScannerController(
      torchEnabled: _flashEnabled,
      facing: _cameraFacingFront ? CameraFacing.front : CameraFacing.back,
      returnImage: false,
    );

    _loadScanHistory();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _scanCooldownTimer?.cancel();
    _ticketIdController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadScanHistory() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Попробуем получить данные с вложенным запросом
      try {
        final response = await _supabase
            .from('ticket_usage')
            .select('''
            id,
            ticket_id,
            used_date,
            used_time,
            scanned_by,
            tickets!inner(
              id,
              student_id,
              used_days,
              profiles!inner(
                full_name,
                student_group,
                student_speciality
              )
            )
          ''')
            .eq('scanned_by', user.id)
            .not('used_time', 'is', null)
            .order('used_time', ascending: false)
            .limit(10);

        if (response != null && response.isNotEmpty) {
          setState(() {
            _scanHistory = List<Map<String, dynamic>>.from(response);
          });
          return;
        }
      } catch (innerError) {
        debugPrint('Inner query error: $innerError');
        // Если не сработало, попробуем другой способ
      }

      // Fallback: загружаем данные отдельными запросами
      final response = await _supabase
          .from('ticket_usage')
          .select('id, ticket_id, used_date, used_time, scanned_by')
          .eq('scanned_by', user.id)
          .not('used_time', 'is', null)
          .order('used_time', ascending: false)
          .limit(10);

      if (response != null && response.isNotEmpty) {
        final List<Map<String, dynamic>> enrichedHistory = [];

        for (var scan in response) {
          final Map<String, dynamic> enrichedScan = Map<String, dynamic>.from(scan);

          // Получаем информацию о талоне и студенте
          try {
            final ticketId = scan['ticket_id'];
            final ticketResponse = await _supabase
                .from('tickets')
                .select('''
                id,
                student_id,
                used_days,
                profiles!inner(
                  full_name,
                  student_group,
                  student_speciality
                )
              ''')
                .eq('id', ticketId)
                .maybeSingle();

            if (ticketResponse != null) {
              enrichedScan['tickets'] = ticketResponse;
            }
          } catch (e) {
            debugPrint('Error loading ticket info: $e');
          }

          enrichedHistory.add(enrichedScan);
        }

        setState(() {
          _scanHistory = enrichedHistory;
        });
      }
    } catch (error) {
      debugPrint('Error loading scan history: $error');
    }
  }

  void _onBarcodeDetected(BarcodeCapture barcodes) {
    if (_isProcessing) return;

    final barcode = barcodes.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final payload = barcode.rawValue!;
    _processQrPayload(payload);
  }

  void _processQrPayload(String payload) {
    try {
      // Format from TicketsScreen: TICKET:ticket_id:token
      if (payload.startsWith('TICKET:')) {
        final parts = payload.substring(7).split(':');
        if (parts.length >= 2) {
          final ticketId = parts[0];
          final token = parts[1];
          _validateAndUseTicket(ticketId, token);
          return;
        }
      }

      // Try JSON format
      try {
        final jsonData = jsonDecode(payload) as Map<String, dynamic>;
        final ticketId = jsonData['ticket_id']?.toString();
        final token = jsonData['token']?.toString();

        if (ticketId != null && token != null) {
          _validateAndUseTicket(ticketId, token);
          return;
        }
      } catch (_) {
        // Not JSON
      }

      // Simple format: ticket_id:token
      final parts = payload.split(':');
      if (parts.length == 2) {
        _validateAndUseTicket(parts[0], parts[1]);
        return;
      }

      _showError('Неверный формат QR-кода. Используйте: TICKET:id:token');
    } catch (e) {
      _showError('Ошибка обработки: $e');
    }
  }

  Future<void> _validateAndUseTicket(String ticketId, String token) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _resultMessage = null;
      _success = null;
      _scannedData = null;
      _studentInfo = null;
    });

    try {
      final cashier = _supabase.auth.currentUser;
      if (cashier == null) throw Exception('Кассир не авторизован');

      debugPrint('Проверяем талон: ticketId=$ticketId, token=$token');

      // 1. Сначала проверяем, существует ли талон
      final ticketResponse = await _supabase
          .from('tickets')
          .select('*')
          .eq('id', ticketId)
          .eq('is_active', true)
          .maybeSingle();

      if (ticketResponse == null) {
        throw Exception('Талон не найден или не активен');
      }

      // 2. Проверяем QR-код
      final today = DateTime.now().toIso8601String().split('T')[0];
      final qrResponse = await _supabase
          .from('daily_qr_codes')
          .select('*')
          .eq('ticket_id', ticketId)
          .eq('token', token)
          .eq('used', false)
          .maybeSingle();

      if (qrResponse == null) {
        throw Exception('QR-код не найден или уже использован');
      }

      // 3. Проверяем дату (используем локальное время)
      final now = DateTime.now().toLocal();
      final qrDate = qrResponse['date']?.toString().split('T')[0];

      if (qrDate != today) {
        throw Exception('QR-код не для сегодня. Дата QR: $qrDate, сегодня: $today');
      }

      // 4. Проверяем срок действия (используем локальное время)
      final expiresAt = DateTime.parse(qrResponse['expires_at']).toLocal();
      if (now.isAfter(expiresAt)) {
        throw Exception('QR-код просрочен. Истекает: ${DateFormat('HH:mm').format(expiresAt)}');
      }

      // 5. Получаем информацию о студенте
      final studentResponse = await _supabase
          .from('profiles')
          .select('full_name, student_group, student_speciality')
          .eq('id', ticketResponse['student_id'])
          .single();

      // 6. Подтверждение сканирования
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Подтверждение'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Студент: ${studentResponse['full_name']}'),
              Text('Группа: ${studentResponse['student_group']}'),
              Text('Специальность: ${studentResponse['student_speciality']}'),
              const SizedBox(height: 16),
              const Text('Подтвердите использование талона'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        throw Exception('Сканирование отменено');
      }

      // 7. Вызываем функцию
      final result = await _supabase.rpc('use_ticket_today_fixed', params: {
        'p_ticket_id': ticketId,
        'p_cashier_id': cashier.id,
        'p_token': token,
      });

      if (result == null || result['success'] != true) {
        throw Exception(result?['message'] ?? 'Ошибка при использовании талона');
      }

      // Успех
      setState(() {
        _success = true;
        _resultMessage = 'Талон успешно использован!';
        _scannedData = ticketResponse;
        _studentInfo = studentResponse;
      });

      await _loadScanHistory();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Можно использовать Provider, EventBus или просто обновить данные
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Талон использован. Обновите экран талонов.'),
            backgroundColor: AppColors.success,
          ),
        );
      });

    } catch (error) {
      debugPrint('Ошибка сканирования: $error');
      setState(() {
        _success = false;
        _resultMessage = error.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleFlash() {
    setState(() {
      _flashEnabled = !_flashEnabled;
      _scannerController.toggleTorch();
    });
  }

  void _switchCamera() {
    setState(() {
      _cameraFacingFront = !_cameraFacingFront;
      _scannerController.switchCamera();
    });
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await FlutterClipboard.paste();
      if (data.isNotEmpty) {
        _processQrPayload(data);
      }
    } catch (e) {
      _showError('Не удалось вставить из буфера');
    }
  }

  void _manualUseTicket() {
    final ticketId = _ticketIdController.text.trim();
    final token = _tokenController.text.trim();

    if (ticketId.isEmpty || token.isEmpty) {
      _showError('Заполните ID талона и токен');
      return;
    }

    _validateAndUseTicket(ticketId, token);
  }

  Widget _buildScannerView() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetected,
            fit: BoxFit.cover,
          ),

          // Scan frame overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: CustomPaint(
                painter: _ScanFramePainter(),
              ),
            ),
          ),

          // Status text
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black.withOpacity(0.5),
              child: Text(
                _isProcessing ? 'Обработка...' : 'Наведите камеру на QR-код',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: _toggleFlash,
            icon: Icon(
              _flashEnabled ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
              size: 28,
            ),
            tooltip: _flashEnabled ? 'Выключить вспышку' : 'Включить вспышку',
          ),
          IconButton(
            onPressed: _switchCamera,
            icon: const Icon(
              Icons.cameraswitch,
              color: Colors.white,
              size: 28,
            ),
            tooltip: 'Переключить камеру',
          ),
          IconButton(
            onPressed: _pasteFromClipboard,
            icon: const Icon(
              Icons.paste,
              color: Colors.white,
              size: 28,
            ),
            tooltip: 'Вставить из буфера',
          ),
        ],
      ),
    );
  }

  Widget _buildManualInput() {
    return ModernCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ручной ввод',
            style: AppTypography.titleLarge.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ticketIdController,
            decoration: InputDecoration(
              labelText: 'ID талона',
              prefixIcon: const Icon(Icons.confirmation_number),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            decoration: InputDecoration(
              labelText: 'Токен',
              prefixIcon: const Icon(Icons.vpn_key),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _manualUseTicket,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                'ИСПОЛЬЗОВАТЬ ТАЛОН',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultIndicator() {
    if (_resultMessage == null) return const SizedBox();

    return ModernCard(
      padding: const EdgeInsets.all(16),
      backgroundColor: _success == true
          ? AppColors.success.withOpacity(0.1)
          : AppColors.error.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            _success == true ? Icons.check_circle : Icons.error,
            color: _success == true ? AppColors.success : AppColors.error,
            size: 36,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _success == true ? 'Успешно!' : 'Ошибка',
                  style: AppTypography.titleMedium.copyWith(
                    color: _success == true ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _resultMessage!,
                  style: AppTypography.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketInfo() {
    if (_scannedData == null || _studentInfo == null) return const SizedBox();

    final startDate = DateTime.parse(_scannedData!['start_date']);
    final endDate = DateTime.parse(_scannedData!['end_date']);
    final totalDays = endDate.difference(startDate).inDays + 1;
    final usedDays = _scannedData!['used_days'] ?? 0;

    return ModernCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Информация о талоне',
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Студент:', _studentInfo!['full_name']),
          _buildInfoRow('Группа:', _studentInfo!['student_group']),
          _buildInfoRow('Специальность:', _studentInfo!['student_speciality']),
          _buildInfoRow(
            'Период действия:',
            '${DateFormat('dd.MM.yyyy').format(startDate)} - ${DateFormat('dd.MM.yyyy').format(endDate)}',
          ),
          _buildInfoRow('Всего дней:', '$totalDays'),
          _buildInfoRow('Использовано дней:', '$usedDays'),
          _buildInfoRow('Осталось дней:', '${totalDays - usedDays}'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    if (_scanHistory.isEmpty) return const SizedBox();

    return ModernCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'История сканирований',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadScanHistory,
                iconSize: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._scanHistory.map((scan) {
            final date = DateTime.parse(scan['used_time']);
            final studentInfo = scan['tickets']?['profiles'];

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentInfo?['full_name'] ?? 'Студент',
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${DateFormat('dd.MM.yyyy').format(date)} в ${DateFormat('HH:mm').format(date)}',
                          style: AppTypography.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканирование талонов'),
        centerTitle: true,
        actions: [
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Scanner
            _buildScannerView(),
            _buildControls(),
            const SizedBox(height: 20),

            // Results
            if (_resultMessage != null) ...[
              _buildResultIndicator(),
              const SizedBox(height: 16),
            ],

            // Ticket info
            if (_scannedData != null) ...[
              _buildTicketInfo(),
              const SizedBox(height: 16),
            ],

            // Manual input
            _buildManualInput(),
            const SizedBox(height: 20),

            // History
            _buildHistory(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw corners
    const cornerLength = 20.0;

    // Top-left
    canvas.drawLine(Offset.zero, Offset(cornerLength, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, cornerLength), paint);

    // Top-right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), paint);

    // Bottom-left
    canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLength), paint);

    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ModernCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  const ModernCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: backgroundColor,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}