import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class TankDataTab extends StatefulWidget {
  const TankDataTab({super.key});
  @override
  State<TankDataTab> createState() => _TankDataTabState();
}

class _TankDataTabState extends State<TankDataTab> {
  final _supabase = Supabase.instance.client;
  int _selectedTankId = 1;
  List<Map<String, dynamic>> _tanks = [];
  List<Map<String, dynamic>> _recipes = [];
  bool _isLoading = true;
  bool _isLoadingDetails = false;

  Map<String, dynamic>? _activeBatch;
  List<Map<String, dynamic>> _fermentationLogs = [];
  List<Map<String, dynamic>> _allMasterItems = [];

  // --- 仕込み実績(batches) ---
  final _startTimeC = TextEditingController();
  String? _dbStartTimeStr;
  final _initialTempC = TextEditingController();
  final _initialPhC = TextEditingController();
  final _ogC = TextEditingController();
  final _fgC = TextEditingController();
  final _abvC = TextEditingController();
  final _mashWaterC = TextEditingController();
  final _spargeWaterC = TextEditingController();
  final _preBoilC = TextEditingController();
  final _postBoilC = TextEditingController();
  final _fermenterVolC = TextEditingController();

  // ★追加: 現在のバッチ用メモ
  final _batchMemoC = TextEditingController();

  // --- 発酵記録(fermentation_logs) ---
  final _logTempC = TextEditingController();
  final _logGravityC = TextEditingController();
  final _logPhC = TextEditingController();
  final _logDumpC = TextEditingController();

  String _selectedAction = '計測・確認';
  final List<String> _actionOptions = [
    '計測・確認',
    'ダンプ (Yeast/Trub)',
    '添加 (Dry Hop/副原料)',
    'その他',
  ];
  final _logActionC = TextEditingController();
  final _logMemoC = TextEditingController();

  String? _selectedCategory;
  String? _selectedItem;
  final _addedAmountC = TextEditingController();

  final Map<String, String> _categories = {
    'A': '副材料',
    'C': '薬品',
    'H': 'ホップ',
    'M': '麦芽',
    'N': '栄養剤',
    'P': '資材',
    'Y': '酵母',
  };

  @override
  void initState() {
    super.initState();
    _fetchAllMasterItems();
    _fetchData();
  }

  Future<void> _fetchAllMasterItems() async {
    final data = await _supabase
        .from('item_master')
        .select()
        .order('category_code')
        .order('name');
    if (mounted)
      setState(() => _allMasterItems = List<Map<String, dynamic>>.from(data));
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final tResponse = await _supabase.from('tanks').select().order('id');
      final rResponse = await _supabase.from('recipes').select().order('name');

      _tanks = List<Map<String, dynamic>>.from(tResponse);
      _recipes = List<Map<String, dynamic>>.from(rResponse);

      if (_tanks.isNotEmpty && !_tanks.any((t) => t['id'] == _selectedTankId)) {
        _selectedTankId = _tanks.first['id'];
      }

      await _fetchTankDetails();
    } catch (e) {
      debugPrint('データ取得エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTankDetails() async {
    setState(() => _isLoadingDetails = true);
    try {
      final currentTank = _tanks.firstWhere((t) => t['id'] == _selectedTankId);
      final batchData = await _supabase
          .from('batches')
          .select()
          .eq('tank_id', _selectedTankId.toString())
          .eq('status', 'Fermenting')
          .maybeSingle();

      if (batchData != null) {
        _activeBatch = batchData;

        _dbStartTimeStr = currentTank['start_time'];
        if (_dbStartTimeStr != null) {
          final dt = DateTime.parse(_dbStartTimeStr!).toLocal();
          _startTimeC.text =
              '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }

        _initialTempC.text = batchData['initial_temp']?.toString() ?? '';
        _initialPhC.text = batchData['initial_ph']?.toString() ?? '';
        _ogC.text = batchData['original_gravity']?.toString() ?? '';
        _fgC.text = batchData['final_gravity']?.toString() ?? '';
        _abvC.text = batchData['abv']?.toString() ?? '';
        _mashWaterC.text = batchData['mash_water_l']?.toString() ?? '';
        _spargeWaterC.text = batchData['sparge_water_l']?.toString() ?? '';
        _preBoilC.text = batchData['pre_boil_vol_l']?.toString() ?? '';
        _postBoilC.text = batchData['post_boil_vol_l']?.toString() ?? '';
        _fermenterVolC.text = batchData['fermenter_vol_l']?.toString() ?? '';
        _batchMemoC.text = batchData['memo'] ?? ''; // ★追加: メモを読み込む

        final logsData = await _supabase
            .from('fermentation_logs')
            .select()
            .eq('batch_id', batchData['id'])
            .order('log_time', ascending: false);
        _fermentationLogs = List<Map<String, dynamic>>.from(logsData);
      } else {
        _activeBatch = null;
        _fermentationLogs = [];
        _startTimeC.clear();
        _initialTempC.clear();
        _initialPhC.clear();
        _ogC.clear();
        _fgC.clear();
        _abvC.clear();
        _mashWaterC.clear();
        _spargeWaterC.clear();
        _preBoilC.clear();
        _postBoilC.clear();
        _fermenterVolC.clear();
        _batchMemoC.clear(); // ★追加: 空ならメモもリセット
      }
    } catch (e) {
      debugPrint('詳細取得エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _pickStartTime() async {
    DateTime initialDate = DateTime.now();
    if (_dbStartTimeStr != null)
      initialDate =
          DateTime.tryParse(_dbStartTimeStr!)?.toLocal() ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.black),
        ),
        child: child!,
      ),
    );

    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
        builder: (context, child) => Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.black),
          ),
          child: child!,
        ),
      );
      if (pickedTime != null) {
        final finalDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        setState(() {
          _dbStartTimeStr = finalDateTime.toUtc().toIso8601String();
          _startTimeC.text =
              '${finalDateTime.year}/${finalDateTime.month.toString().padLeft(2, '0')}/${finalDateTime.day.toString().padLeft(2, '0')} ${finalDateTime.hour.toString().padLeft(2, '0')}:${finalDateTime.minute.toString().padLeft(2, '0')}';
        });
      }
    }
  }

  // ★追加: メモだけを即座に保存する機能
  Future<void> _updateBatchMemo() async {
    if (_activeBatch == null) return;
    try {
      await _supabase
          .from('batches')
          .update({'memo': _batchMemoC.text})
          .eq('id', _activeBatch!['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('バッチメモを保存しました！')));
      _fetchTankDetails();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  Future<void> _updateBatchDetails() async {
    if (_activeBatch == null) return;
    try {
      await _supabase
          .from('batches')
          .update({
            'initial_temp': double.tryParse(_initialTempC.text),
            'initial_ph': double.tryParse(_initialPhC.text),
            'original_gravity': double.tryParse(_ogC.text),
            'final_gravity': double.tryParse(_fgC.text),
            'abv': double.tryParse(_abvC.text),
            'mash_water_l': double.tryParse(_mashWaterC.text),
            'sparge_water_l': double.tryParse(_spargeWaterC.text),
            'pre_boil_vol_l': double.tryParse(_preBoilC.text),
            'post_boil_vol_l': double.tryParse(_postBoilC.text),
            'fermenter_vol_l': double.tryParse(_fermenterVolC.text),
          })
          .eq('id', _activeBatch!['id']);

      if (_dbStartTimeStr != null)
        await _supabase
            .from('tanks')
            .update({'start_time': _dbStartTimeStr})
            .eq('id', _selectedTankId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('仕込み実績データを更新しました！')));
      _fetchData();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  Future<void> _addFermentationLog() async {
    if (_activeBatch == null) return;
    double? addedAmount;
    String? unit;
    String actionText = _selectedAction;

    if (_selectedAction == '添加 (Dry Hop/副原料)') {
      if (_selectedItem == null || _addedAmountC.text.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('追加する材料と数量を入力してください')));
        return;
      }
      addedAmount = double.tryParse(_addedAmountC.text);
      if (addedAmount == null || addedAmount <= 0) return;

      final masterRes = await _supabase
          .from('item_master')
          .select('name, unit')
          .eq('id', _selectedItem!)
          .maybeSingle();
      final itemName = masterRes != null ? masterRes['name'] : '不明な材料';
      unit = masterRes != null ? masterRes['unit'] : 'kg';

      final txs = await _supabase
          .from('inventory_transactions')
          .select('transaction_type, amount')
          .eq('item_id', _selectedItem!);
      double currentStock = 0.0;
      for (var tx in txs) {
        final amt = (tx['amount'] as num).toDouble();
        if (tx['transaction_type'] == 'IN')
          currentStock += amt;
        else
          currentStock -= amt;
      }
      if (currentStock < addedAmount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ 在庫が足りません！\n$itemName の現在庫は ${currentStock.toStringAsFixed(1)} $unit です。',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
      actionText = '添加: $itemName ($addedAmount $unit)';
    } else if (_selectedAction == 'その他') {
      actionText = _logActionC.text;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await _supabase.from('fermentation_logs').insert({
        'batch_id': _activeBatch!['id'],
        'log_time': DateTime.now().toIso8601String(),
        'temperature': double.tryParse(_logTempC.text),
        'gravity': double.tryParse(_logGravityC.text),
        'ph': double.tryParse(_logPhC.text),
        'dumped_vol_l': double.tryParse(_logDumpC.text),
        'action': actionText,
        'memo': _logMemoC.text,
      });

      if (_selectedAction == '添加 (Dry Hop/副原料)') {
        await _supabase.from('batch_ingredients').insert({
          'batch_id': _activeBatch!['id'],
          'item_id': _selectedItem,
          'amount_used': addedAmount,
        });
        final currentTank = _tanks.firstWhere(
          (t) => t['id'] == _selectedTankId,
          orElse: () => {},
        );
        final customBatchId = currentTank['current_batch_id'] ?? 'N/A';
        await _supabase.from('inventory_transactions').insert({
          'item_id': _selectedItem,
          'transaction_type': 'OUT',
          'amount': addedAmount,
          'unit': unit,
          'price': 0,
          'memo': 'TANK $_selectedTankId $customBatchId への追加投入',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      _logTempC.clear();
      _logGravityC.clear();
      _logPhC.clear();
      _logDumpC.clear();
      _logActionC.clear();
      _logMemoC.clear();
      _addedAmountC.clear();
      setState(() {
        _selectedAction = '計測・確認';
        _selectedCategory = null;
        _selectedItem = null;
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('計測記録を追加しました！')));
      _fetchTankDetails();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _startBrew(Map<String, dynamic> recipe) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
    try {
      final recipeId = recipe['id'];
      final recipeName = recipe['name'];
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final recipeItems = await _supabase
          .from('recipe_items')
          .select()
          .eq('recipe_id', recipeId);

      List<String> shortageMessages = [];
      List<Map<String, dynamic>> validatedItems = [];
      for (var item in recipeItems) {
        final itemId = item['item_id'];
        final requiredAmount = (item['amount'] as num).toDouble();
        final masterRes = await _supabase
            .from('item_master')
            .select('name, unit')
            .eq('id', itemId)
            .maybeSingle();
        final itemName = masterRes != null ? masterRes['name'] : '不明な材料';
        final unit = masterRes != null ? masterRes['unit'] : 'kg';
        final txs = await _supabase
            .from('inventory_transactions')
            .select('transaction_type, amount')
            .eq('item_id', itemId);
        double currentStock = 0.0;
        for (var tx in txs) {
          final amt = (tx['amount'] as num).toDouble();
          if (tx['transaction_type'] == 'IN')
            currentStock += amt;
          else
            currentStock -= amt;
        }
        if (currentStock < requiredAmount) {
          shortageMessages.add(
            '・$itemName: ${(requiredAmount - currentStock).toStringAsFixed(1)}$unit 不足\n   (現在庫: ${currentStock.toStringAsFixed(1)} / 必要: $requiredAmount)',
          );
        } else {
          validatedItems.add({
            'item_id': itemId,
            'amount': requiredAmount,
            'unit': unit,
          });
        }
      }

      if (shortageMessages.isNotEmpty) {
        if (!mounted) return;
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(
              '⚠️ 在庫が足りません！',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('以下の材料が不足しています。'),
                const SizedBox(height: 16),
                ...shortageMessages.map(
                  (msg) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      msg,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('確認 (CLOSE)'),
              ),
            ],
          ),
        );
        return;
      }

      final countData = await _supabase
          .from('batches')
          .select('id')
          .eq('recipe_id', recipeId);
      final customBatchNo = '${recipeName}_${countData.length + 1}';
      final newBatch = await _supabase
          .from('batches')
          .insert({
            'tank_id': _selectedTankId.toString(),
            'recipe_id': recipeId,
            'beer_name': recipeName,
            'brew_date': todayStr,
            'status': 'Fermenting',
          })
          .select()
          .single();
      final newBatchId = newBatch['id'];

      await _supabase
          .from('tanks')
          .update({
            'current_recipe': recipeName,
            'current_batch_id': customBatchNo,
            'start_time': DateTime.now().toUtc().toIso8601String(),
            'status': 'FERMENTING',
          })
          .eq('id', _selectedTankId);

      for (var item in validatedItems) {
        await _supabase.from('batch_ingredients').insert({
          'batch_id': newBatchId,
          'item_id': item['item_id'],
          'amount_used': item['amount'],
        });
        await _supabase.from('inventory_transactions').insert({
          'item_id': item['item_id'],
          'transaction_type': 'OUT',
          'amount': item['amount'],
          'unit': item['unit'],
          'price': 0,
          'memo': 'TANK $_selectedTankId $customBatchNo の仕込みによる自動出庫',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('仕込み完了！$customBatchNo として登録しました🍺')),
      );
      _fetchData();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _calculateElapsedTime(String? startTimeStr) {
    if (startTimeStr == null) return 'N/A';
    final startTime = DateTime.parse(startTimeStr).toLocal();
    final duration = DateTime.now().difference(startTime);
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    return '${days}日 ${hours}時間';
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    final dt = DateTime.parse(dateStr).toLocal();
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusItem(
    String label,
    String value, {
    Color? valueColor,
    String? subText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: valueColor ?? Colors.black87,
          ),
        ),
        if (subText != null)
          Text(
            subText,
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
      ],
    );
  }

  Widget _buildMiniBadge(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: ${value ?? '-'}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[800],
        ),
      ),
    );
  }

  Widget _buildMiniChart(String title, List<FlSpot> spots, Color color) {
    if (spots.isEmpty) return const SizedBox.shrink();

    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    } else {
      double pad = (maxY - minY) * 0.2;
      minY -= pad;
      maxY += pad;
    }

    return Container(
      height: 120,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                backgroundColor: Colors.grey[50],
                minX: 0,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.grey[200], strokeWidth: 1),
                  getDrawingVerticalLine: (value) =>
                      FlLine(color: Colors.grey[200], strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}日',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (val, meta) => Text(
                        val.toStringAsFixed(title.contains('SG') ? 3 : 1),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey[300]!),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.15),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );

    final currentTank = _tanks.firstWhere(
      (t) => t['id'] == _selectedTankId,
      orElse: () => {
        'id': _selectedTankId,
        'current_recipe': null,
        'current_batch_id': null,
        'start_time': null,
      },
    );
    final String? rawRecipeName = currentTank['current_recipe'];
    final bool isEmptyTank =
        rawRecipeName == null ||
        rawRecipeName.trim().isEmpty ||
        rawRecipeName.toUpperCase() == 'EMPTY' ||
        rawRecipeName.toUpperCase() == 'ENPTY';

    Map<String, dynamic>? activeRecipeData;
    if (!isEmptyTank) {
      activeRecipeData = _recipes.firstWhere(
        (r) => r['name'] == rawRecipeName,
        orElse: () => <String, dynamic>{},
      );
    }

    double totalDumped = 0.0;
    for (var log in _fermentationLogs) {
      totalDumped += (log['dumped_vol_l'] ?? 0.0) as num;
    }
    final fermenterVol = double.tryParse(_fermenterVolC.text) ?? 0.0;
    final currentVolume = fermenterVol - totalDumped;

    String currentTemp = '-';
    String currentSg = '-';
    String currentPh = '-';

    if (_fermentationLogs.isNotEmpty) {
      currentTemp = _fermentationLogs.first['temperature']?.toString() ?? '-';
      currentSg = _fermentationLogs.first['gravity']?.toString() ?? '-';
      currentPh = _fermentationLogs.first['ph']?.toString() ?? '-';
    } else if (_activeBatch != null) {
      currentTemp = _activeBatch!['initial_temp']?.toString() ?? '-';
      currentSg = _activeBatch!['original_gravity']?.toString() ?? '-';
      currentPh = _activeBatch!['initial_ph']?.toString() ?? '-';
    }

    bool showDumpInput =
        _selectedAction == '計測・確認' || _selectedAction == 'ダンプ (Yeast/Trub)';

    List<FlSpot> sgSpots = [];
    List<FlSpot> tempSpots = [];
    List<FlSpot> phSpots = [];

    DateTime? graphStartTime = _dbStartTimeStr != null
        ? DateTime.tryParse(_dbStartTimeStr!)?.toLocal()
        : null;

    if (graphStartTime != null && !isEmptyTank) {
      if (_activeBatch!['original_gravity'] != null)
        sgSpots.add(
          FlSpot(0, (_activeBatch!['original_gravity'] as num).toDouble()),
        );
      if (_activeBatch!['initial_temp'] != null)
        tempSpots.add(
          FlSpot(0, (_activeBatch!['initial_temp'] as num).toDouble()),
        );
      if (_activeBatch!['initial_ph'] != null)
        phSpots.add(FlSpot(0, (_activeBatch!['initial_ph'] as num).toDouble()));

      final sortedLogs = List<Map<String, dynamic>>.from(_fermentationLogs)
        ..sort((a, b) => a['log_time'].compareTo(b['log_time']));

      for (var log in sortedLogs) {
        final logTime = DateTime.parse(log['log_time']).toLocal();
        final double days =
            logTime.difference(graphStartTime).inMinutes / (60.0 * 24.0);

        if (days >= 0) {
          if (log['gravity'] != null)
            sgSpots.add(FlSpot(days, (log['gravity'] as num).toDouble()));
          if (log['temperature'] != null)
            tempSpots.add(FlSpot(days, (log['temperature'] as num).toDouble()));
          if (log['ph'] != null)
            phSpots.add(FlSpot(days, (log['ph'] as num).toDouble()));
        }
      }
    }

    return Row(
      children: [
        // --- 左側: タンク選択リスト ---
        Container(
          width: 120,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Colors.black, width: 2)),
          ),
          child: _tanks.isEmpty
              ? const Center(child: Text('No Tank'))
              : ListView.builder(
                  itemCount: _tanks.length,
                  itemBuilder: (context, i) {
                    final t = _tanks[i];
                    final isSel = _selectedTankId == t['id'];
                    final String tRecipe =
                        t['current_recipe']?.toString() ?? '';
                    final bool tIsEmpty =
                        tRecipe.isEmpty ||
                        tRecipe.toUpperCase() == 'EMPTY' ||
                        tRecipe.toUpperCase() == 'ENPTY';

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedTankId = t['id']);
                        _fetchData();
                      },
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: isSel ? Colors.black : Colors.white,
                          border: const Border(
                            bottom: BorderSide(color: Colors.black12),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'TANK ${t['id']}',
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              tIsEmpty ? 'EMPTY' : tRecipe,
                              style: TextStyle(
                                color: isSel ? Colors.white70 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // --- 右側: 詳細エリア ---
        Expanded(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TANK $_selectedTankId STATUS',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),

                if (isEmptyTank) ...[
                  const Text('タンクは空です。レシピを選択して仕込みを開始してください。'),
                  const SizedBox(height: 20),
                  _recipes.isEmpty
                      ? const Text('レシピが登録されていません')
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _recipes
                              .map(
                                (r) => OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black,
                                    side: const BorderSide(
                                      color: Colors.black,
                                      width: 2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 15,
                                    ),
                                  ),
                                  onPressed: () => _startBrew(r),
                                  child: Text(
                                    r['name'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ] else if (_isLoadingDetails) ...[
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ] else ...[
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rawRecipeName!,
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w900,
                                          height: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'Batch: ${currentTank['current_batch_id'] ?? 'N/A'}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 24,
                                        runSpacing: 16,
                                        children: [
                                          _buildStatusItem(
                                            'BREWED ON',
                                            _formatDate(
                                              currentTank['start_time'],
                                            ),
                                          ),
                                          _buildStatusItem(
                                            'TIME IN TANK',
                                            _calculateElapsedTime(
                                              currentTank['start_time'],
                                            ),
                                            valueColor: Colors.blue[700],
                                          ),
                                          _buildStatusItem(
                                            'CURRENT VOL',
                                            '${currentVolume.toStringAsFixed(1)} L',
                                            valueColor: Colors.green[700],
                                            subText:
                                                'IN $fermenterVol L - DUMP $totalDumped L',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 24,
                                        runSpacing: 16,
                                        children: [
                                          _buildStatusItem(
                                            'CURRENT TEMP',
                                            '$currentTemp°C',
                                            valueColor: Colors.orange[800],
                                          ),
                                          _buildStatusItem(
                                            'CURRENT SG',
                                            currentSg,
                                            valueColor: Colors.purple[800],
                                          ),
                                          _buildStatusItem(
                                            'CURRENT pH',
                                            currentPh,
                                            valueColor: Colors.teal[800],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      if (activeRecipeData != null &&
                                          activeRecipeData.isNotEmpty)
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _buildMiniBadge(
                                              'Target OG',
                                              activeRecipeData['target_og'],
                                            ),
                                            _buildMiniBadge(
                                              'Target FG',
                                              activeRecipeData['target_fg'],
                                            ),
                                            _buildMiniBadge(
                                              'ABV',
                                              '${activeRecipeData['target_abv'] ?? '-'}%',
                                            ),
                                            _buildMiniBadge(
                                              'IBU',
                                              activeRecipeData['target_ibu'],
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ==========================================
                          // ★ 追加: 現在のバッチ・メモ欄
                          // ==========================================
                          const Text(
                            '📝 バッチ・メモ (テイスティングノート・特記事項)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _batchMemoC,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    hintText:
                                        '発酵のスピードやドライホップの香り、反省点などを自由に入力...',
                                    border: const OutlineInputBorder(),
                                    fillColor: Colors.grey[50],
                                    filled: true,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: _updateBatchMemo,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 30,
                                  ),
                                ),
                                child: const Text(
                                  'SAVE',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          if (sgSpots.length >= 2 ||
                              tempSpots.length >= 2 ||
                              phSpots.length >= 2) ...[
                            Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '📈 Fermentation Charts (発酵曲線グラフ)',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Divider(),
                                    const SizedBox(height: 8),
                                    _buildMiniChart(
                                      'Gravity (比重 SG)',
                                      sgSpots,
                                      Colors.purple[700]!,
                                    ),
                                    _buildMiniChart(
                                      'Temperature (液温 °C)',
                                      tempSpots,
                                      Colors.orange[700]!,
                                    ),
                                    _buildMiniChart(
                                      'pH',
                                      phSpots,
                                      Colors.teal[700]!,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ] else ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'ℹ️ データが2回以上入力されると、ここに発酵曲線グラフが表示されます。',
                                style: TextStyle(color: Colors.blue),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          Card(
                            elevation: 0,
                            color: Colors.grey[50],
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        '📊 Batches Update (仕込み実績)',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: _updateBatchDetails,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black87,
                                          minimumSize: const Size(100, 36),
                                        ),
                                        child: const Text(
                                          'UPDATE',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: InkWell(
                                          onTap: _pickStartTime,
                                          child: InputDecorator(
                                            decoration: const InputDecoration(
                                              labelText: 'タンク投入日時',
                                              border: UnderlineInputBorder(),
                                            ),
                                            child: Text(
                                              _startTimeC.text.isNotEmpty
                                                  ? _startTimeC.text
                                                  : '日時を選択',
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _initialTempC,
                                          decoration: const InputDecoration(
                                            labelText: '最初の液温 (°C)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _initialPhC,
                                          decoration: const InputDecoration(
                                            labelText: '最初のpH',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _ogC,
                                          decoration: const InputDecoration(
                                            labelText: 'Original Gravity (OG)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _fgC,
                                          decoration: const InputDecoration(
                                            labelText: 'Final Gravity (FG)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _abvC,
                                          decoration: const InputDecoration(
                                            labelText: 'ABV (%)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _mashWaterC,
                                          decoration: const InputDecoration(
                                            labelText: 'Mash Water (L)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _spargeWaterC,
                                          decoration: const InputDecoration(
                                            labelText: 'Sparge Water (L)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _preBoilC,
                                          decoration: const InputDecoration(
                                            labelText: 'Pre-Boil (L)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _postBoilC,
                                          decoration: const InputDecoration(
                                            labelText: 'Post-Boil (L)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _fermenterVolC,
                                          decoration: const InputDecoration(
                                            labelText: 'タンク投入量 (L)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Card(
                            elevation: 0,
                            color: Colors.grey[50],
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '📝 Fermentation Logs (日々の計測・作業)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Divider(),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _logTempC,
                                          decoration: const InputDecoration(
                                            labelText: 'Temp (°C)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _logGravityC,
                                          decoration: const InputDecoration(
                                            labelText: 'Gravity (SG)',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _logPhC,
                                          decoration: const InputDecoration(
                                            labelText: 'pH',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (showDumpInput)
                                        Expanded(
                                          child: TextField(
                                            controller: _logDumpC,
                                            decoration: const InputDecoration(
                                              labelText: 'Dump Vol (L)',
                                              hintText: '0.2',
                                            ),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                          ),
                                        )
                                      else
                                        const Spacer(),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: DropdownButtonFormField<String>(
                                          value: _selectedAction,
                                          decoration: const InputDecoration(
                                            labelText: 'Action (作業内容)',
                                          ),
                                          items: _actionOptions
                                              .map(
                                                (a) => DropdownMenuItem(
                                                  value: a,
                                                  child: Text(a),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) => setState(
                                            () => _selectedAction = v!,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (_selectedAction == 'その他')
                                        Expanded(
                                          flex: 3,
                                          child: TextField(
                                            controller: _logActionC,
                                            decoration: const InputDecoration(
                                              labelText: '内容を入力',
                                            ),
                                          ),
                                        )
                                      else
                                        Expanded(
                                          flex: 3,
                                          child: TextField(
                                            controller: _logMemoC,
                                            decoration: const InputDecoration(
                                              labelText: 'Memo (風味・コメント)',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),

                                  if (_selectedAction ==
                                      '添加 (Dry Hop/副原料)') ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.blueGrey[200]!,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.inventory,
                                            color: Colors.blueGrey,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child:
                                                DropdownButtonFormField<String>(
                                                  value: _selectedCategory,
                                                  decoration:
                                                      const InputDecoration(
                                                        labelText: 'カテゴリ',
                                                        border:
                                                            InputBorder.none,
                                                        isDense: true,
                                                      ),
                                                  items: _categories.entries
                                                      .map(
                                                        (e) => DropdownMenuItem(
                                                          value: e.key,
                                                          child: Text(e.value),
                                                        ),
                                                      )
                                                      .toList(),
                                                  onChanged: (v) =>
                                                      setState(() {
                                                        _selectedCategory = v;
                                                        _selectedItem = null;
                                                      }),
                                                ),
                                          ),
                                          Container(
                                            width: 1,
                                            height: 40,
                                            color: Colors.blueGrey[200],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 2,
                                            child: DropdownButtonFormField<String>(
                                              value: _selectedItem,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    '材料 (Inventoryから引かれます)',
                                                border: InputBorder.none,
                                                isDense: true,
                                              ),
                                              items: _allMasterItems
                                                  .where(
                                                    (m) =>
                                                        m['category_code'] ==
                                                        _selectedCategory,
                                                  )
                                                  .map(
                                                    (m) =>
                                                        DropdownMenuItem<
                                                          String
                                                        >(
                                                          value: m['id']
                                                              .toString(),
                                                          child: Text(
                                                            m['name'],
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) => setState(
                                                () => _selectedItem = v,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 1,
                                            height: 40,
                                            color: Colors.blueGrey[200],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextField(
                                              controller: _addedAmountC,
                                              decoration: const InputDecoration(
                                                labelText: '添加量 (kg, L等)',
                                                border: InputBorder.none,
                                                isDense: true,
                                              ),
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 12),
                                  if (_selectedAction == 'その他')
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _logMemoC,
                                            decoration: const InputDecoration(
                                              labelText: 'Memo (風味・コメント)',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        ElevatedButton.icon(
                                          onPressed: _addFermentationLog,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.amber[600],
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 18,
                                              horizontal: 24,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.add,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          label: const Text(
                                            'ADD LOG',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: ElevatedButton.icon(
                                        onPressed: _addFermentationLog,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.amber[600],
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 18,
                                            horizontal: 32,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.add,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        label: const Text(
                                          'ADD LOG',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 16),

                                  _fermentationLogs.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: Center(
                                            child: Text(
                                              'まだ記録がありません',
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        )
                                      : ListView.separated(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: _fermentationLogs.length,
                                          separatorBuilder: (context, index) =>
                                              const Divider(height: 1),
                                          itemBuilder: (context, index) {
                                            final log =
                                                _fermentationLogs[index];
                                            final dt = DateTime.parse(
                                              log['log_time'],
                                            ).toLocal();
                                            final formattedDate =
                                                '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                                            return ListTile(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 0,
                                                  ),
                                              leading: const Icon(
                                                Icons.timeline,
                                                color: Colors.blueGrey,
                                              ),
                                              title: Text(
                                                'Temp: ${log['temperature'] ?? '-'}°C   |   SG: ${log['gravity'] ?? '-'}   |   pH: ${log['ph'] ?? '-'}   |   Dump: ${log['dumped_vol_l'] ?? 0} L',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              subtitle: Text(
                                                '$formattedDate   ${log['action'] != null && log['action'] != '' ? '▶ ${log['action']}' : ''}   ${log['memo'] != null ? log['memo'] : ''}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      );
                      try {
                        await _supabase
                            .from('tanks')
                            .update({
                              'current_recipe': null,
                              'current_batch_id': null,
                              'start_time': null,
                              'status': 'EMPTY',
                            })
                            .eq('id', _selectedTankId);
                        await _supabase
                            .from('batches')
                            .update({'status': 'Completed'})
                            .eq('tank_id', _selectedTankId.toString())
                            .eq('status', 'Fermenting');

                        if (!mounted) return;
                        Navigator.pop(context);
                        _fetchData();
                      } catch (e) {
                        debugPrint('終了エラー: $e');
                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('エラー: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'EMPTY TANK (タンクを空にして終了)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
