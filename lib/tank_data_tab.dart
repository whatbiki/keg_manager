import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; // 日付フォーマット用（必要に応じてpubspec.yamlに intl: ^0.19.0 等を追加してください）

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

  // --- アクティブなバッチと発酵記録のデータ ---
  Map<String, dynamic>? _activeBatch;
  List<Map<String, dynamic>> _fermentationLogs = [];

  // --- 仕込み実績(batches)入力用のコントローラー ---
  final _ogC = TextEditingController();
  final _fgC = TextEditingController();
  final _abvC = TextEditingController();
  final _mashWaterC = TextEditingController();
  final _spargeWaterC = TextEditingController();
  final _preBoilC = TextEditingController();
  final _postBoilC = TextEditingController();

  // --- 発酵記録(fermentation_logs)入力用のコントローラー ---
  final _logTempC = TextEditingController();
  final _logGravityC = TextEditingController();
  final _logActionC = TextEditingController();
  final _logMemoC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // 1. タンクとレシピ一覧を取得する
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

      // タンク一覧が取れたら、選択中タンクの詳細(バッチ＆ログ)も取りに行く
      await _fetchTankDetails();
    } catch (e) {
      debugPrint('データ取得エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. 選択されたタンクの「現在のバッチ情報」と「発酵ログ」を取得する
  Future<void> _fetchTankDetails() async {
    setState(() => _isLoadingDetails = true);
    try {
      // 現在発酵中のバッチを探す
      final batchData = await _supabase
          .from('batches')
          .select()
          .eq('tank_id', _selectedTankId.toString())
          .eq('status', 'Fermenting')
          .maybeSingle();

      if (batchData != null) {
        _activeBatch = batchData;

        // 入力フォームに現在の値をセット
        _ogC.text = batchData['original_gravity']?.toString() ?? '';
        _fgC.text = batchData['final_gravity']?.toString() ?? '';
        _abvC.text = batchData['abv']?.toString() ?? '';
        _mashWaterC.text = batchData['mash_water_l']?.toString() ?? '';
        _spargeWaterC.text = batchData['sparge_water_l']?.toString() ?? '';
        _preBoilC.text = batchData['pre_boil_vol_l']?.toString() ?? '';
        _postBoilC.text = batchData['post_boil_vol_l']?.toString() ?? '';

        // 発酵ログの取得
        final logsData = await _supabase
            .from('fermentation_logs')
            .select()
            .eq('batch_id', batchData['id'])
            .order('log_time', ascending: false); // 最新順

        _fermentationLogs = List<Map<String, dynamic>>.from(logsData);
      } else {
        // 空のタンクの場合
        _activeBatch = null;
        _fermentationLogs = [];
        _ogC.clear();
        _fgC.clear();
        _abvC.clear();
        _mashWaterC.clear();
        _spargeWaterC.clear();
        _preBoilC.clear();
        _postBoilC.clear();
      }
    } catch (e) {
      debugPrint('詳細取得エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  // ==========================================
  // ★ 仕込み実績データ（batches）の更新処理
  // ==========================================
  Future<void> _updateBatchDetails() async {
    if (_activeBatch == null) return;
    try {
      await _supabase
          .from('batches')
          .update({
            'original_gravity': double.tryParse(_ogC.text),
            'final_gravity': double.tryParse(_fgC.text),
            'abv': double.tryParse(_abvC.text),
            'mash_water_l': double.tryParse(_mashWaterC.text),
            'sparge_water_l': double.tryParse(_spargeWaterC.text),
            'pre_boil_vol_l': double.tryParse(_preBoilC.text),
            'post_boil_vol_l': double.tryParse(_postBoilC.text),
          })
          .eq('id', _activeBatch!['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('仕込み実績データを更新しました！')));
      _fetchTankDetails();
    } catch (e) {
      debugPrint('バッチ更新エラー: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  // ==========================================
  // ★ 日々の発酵記録（fermentation_logs）の追加処理
  // ==========================================
  Future<void> _addFermentationLog() async {
    if (_activeBatch == null) return;
    try {
      await _supabase.from('fermentation_logs').insert({
        'batch_id': _activeBatch!['id'],
        'log_time': DateTime.now().toIso8601String(),
        'temperature': double.tryParse(_logTempC.text),
        'gravity': double.tryParse(_logGravityC.text),
        'action': _logActionC.text,
        'memo': _logMemoC.text,
      });

      // 入力欄をクリア
      _logTempC.clear();
      _logGravityC.clear();
      _logActionC.clear();
      _logMemoC.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('計測記録を追加しました！')));
      _fetchTankDetails(); // ログリストを再取得
    } catch (e) {
      debugPrint('ログ追加エラー: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  // --- 仕込み開始処理（在庫ストッパー機能付き・前回と同じ） ---
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
          final shortage = requiredAmount - currentStock;
          shortageMessages.add(
            '・$itemName: ${shortage.toStringAsFixed(1)}$unit 不足\n   (現在庫: ${currentStock.toStringAsFixed(1)} / 必要: $requiredAmount)',
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
      final nextNum = countData.length + 1;
      final customBatchNo = '${recipeName}_$nextNum';

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
          'memo': 'Batch $customBatchNo ($recipeName) の仕込みによる自動出庫',
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
      debugPrint('仕込みエラー: $e');
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildTargetBadge(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blueGrey[200]!),
      ),
      child: Text(
        '$label: ${value ?? '-'}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey[800],
        ),
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
                        _fetchTankDetails(); // タップした瞬間に詳細を取り直す
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

        // --- 右側: 詳細・レシピ登録 ---
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
                  // タンク使用中の場合（スクロール可能な詳細エリア）
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. ヘッダーとTarget情報
                          Text(
                            rawRecipeName!,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Batch No: ${currentTank['current_batch_id'] ?? 'N/A'}',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                          ),
                          if (activeRecipeData != null &&
                              activeRecipeData.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildTargetBadge(
                                  'Target OG',
                                  activeRecipeData['target_og'],
                                ),
                                _buildTargetBadge(
                                  'Target FG',
                                  activeRecipeData['target_fg'],
                                ),
                                _buildTargetBadge(
                                  'ABV',
                                  '${activeRecipeData['target_abv'] ?? '-'}%',
                                ),
                                _buildTargetBadge(
                                  'IBU',
                                  activeRecipeData['target_ibu'],
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 24),

                          // 2. 実測値(batches)の入力フォーム
                          Card(
                            elevation: 2,
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
                                        '📊 仕込み実績データ (Batches Update)',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: _updateBatchDetails,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueGrey[800],
                                        ),
                                        child: const Text(
                                          'UPDATE',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  Row(
                                    children: [
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
                                      const SizedBox(width: 8),
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
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
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
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 3. 発酵記録(fermentation_logs)の追加と履歴
                          Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '📝 日々の計測・作業記録 (Fermentation Logs)',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Divider(),
                                  Row(
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
                                          controller: _logActionC,
                                          decoration: const InputDecoration(
                                            labelText: 'Action (Dry Hop等)',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: _logMemoC,
                                          decoration: const InputDecoration(
                                            labelText: 'Memo (風味など)',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: _addFermentationLog,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.amber[700],
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                            horizontal: 16,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.add,
                                          color: Colors.white,
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
                                  ),
                                  const SizedBox(height: 16),
                                  // 履歴リスト
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
                                      : ListView.builder(
                                          shrinkWrap:
                                              true, // Cardの中でListViewを使うおまじない
                                          physics:
                                              const NeverScrollableScrollPhysics(), // スクロールは親に任せる
                                          itemCount: _fermentationLogs.length,
                                          itemBuilder: (context, index) {
                                            final log =
                                                _fermentationLogs[index];
                                            // 日付を見やすくフォーマット (例: 2026-05-07 10:30)
                                            final DateTime dt = DateTime.parse(
                                              log['log_time'],
                                            ).toLocal();
                                            final String formattedDate =
                                                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                                            return ListTile(
                                              leading: const Icon(
                                                Icons.history,
                                                color: Colors.blueGrey,
                                              ),
                                              title: Text(
                                                'Temp: ${log['temperature'] ?? '-'}°C  |  SG: ${log['gravity'] ?? '-'}',
                                              ),
                                              subtitle: Text(
                                                '$formattedDate  ${log['action'] != null ? ' | Action: ${log['action']}' : ''} ${log['memo'] != null ? ' | ${log['memo']}' : ''}',
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

                  // 終了ボタン（最下部に固定）
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
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
                      'Empty Tank (終了)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
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
