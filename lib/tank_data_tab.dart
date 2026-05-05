import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // 1. タンクとレシピを同時に取得
      final tResponse = await _supabase.from('tanks').select().order('id');
      final rResponse = await _supabase.from('recipes').select().order('name');

      setState(() {
        // 2. タンクデータの受け取り（nullガード付き）
        _tanks = List<Map<String, dynamic>>.from(tResponse);
        // 3. レシピデータの受け取り（nullガード付き）
        _recipes = List<Map<String, dynamic>>.from(rResponse);

        // 4. タンクが存在する場合のみ、初期選択IDをセット
        if (_tanks.isNotEmpty) {
          _selectedTankId = _tanks.first['id'];
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('データ取得に失敗しました: $e'); // 開発中だけ見えるエラーログ
      setState(() => _isLoading = false);
    }
  }

  // 仕込み開始（レシピ登録）処理
  Future<void> _startBrew(String recipeName) async {
    // バッチ番号の生成（簡易例：現在のレシピ数+1など。実際は日付+連番が望ましいです）
    final batchNo =
        '${recipeName}_${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}';

    await _supabase
        .from('tanks')
        .update({
          'current_recipe': recipeName,
          'current_batch_id': batchNo,
          'start_time': DateTime.now().toUtc().toIso8601String(),
          'status': 'FERMENTING',
        })
        .eq('id', _selectedTankId);

    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );

    // --- 【修正ポイント】見つからない場合の回避策を追加 ---
    final currentTank = _tanks.firstWhere(
      (t) => t['id'] == _selectedTankId,
      orElse: () => {
        'id': _selectedTankId,
        'current_recipe': null,
        'current_batch_id': 'N/A',
      },
    );

    final String? recipe = currentTank['current_recipe'];

    return Row(
      children: [
        // --- 左側: タンク選択リスト ---
        Container(
          width: 120,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Colors.black, width: 2)),
          ),
          child: _tanks.isEmpty
              ? const Center(child: Text('No Tank')) // タンクが0件の場合
              : ListView.builder(
                  itemCount: _tanks.length,
                  itemBuilder: (context, i) {
                    final t = _tanks[i];
                    final isSel = _selectedTankId == t['id'];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTankId = t['id']),
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
                              t['current_recipe'] ?? 'EMPTY',
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
                const SizedBox(height: 30),

                if (recipe == null) ...[
                  const Text('タンクは空です。レシピを選択して仕込みを開始してください。'),
                  const SizedBox(height: 20),
                  _recipes.isEmpty
                      ? const Text('レシピが登録されていません（SETタブで作成してください）')
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
                                  onPressed: () => _startBrew(r['name']),
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
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipe,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Batch No: ${currentTank['current_batch_id'] ?? 'N/A'}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const Divider(height: 40, color: Colors.black),
                        const Text('発酵グラフと計測フォーム（準備中）'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      await _supabase
                          .from('tanks')
                          .update({
                            'current_recipe': null,
                            'current_batch_id': null,
                            'start_time': null,
                            'status': 'EMPTY',
                          })
                          .eq('id', _selectedTankId);
                      _fetchData();
                    },
                    child: const Text('Empty Tank (終了)'),
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
