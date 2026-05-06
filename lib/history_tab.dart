import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});
  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _allBatches = [];
  List<Map<String, dynamic>> _recipes = [];
  List<Map<String, dynamic>> _currentBatchLogs = [];

  String _selectedRecipeId = 'ALL';
  int? _selectedBatchId;
  final TextEditingController _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchHistoryData();
  }

  Future<void> _fetchHistoryData() async {
    setState(() => _isLoading = true);
    try {
      // レシピとバッチを取得
      final rRes = await _supabase.from('recipes').select().order('name');
      final bRes = await _supabase
          .from('batches')
          .select()
          .order('id', ascending: true); // 古い順で取得して連番を計算

      _recipes = List<Map<String, dynamic>>.from(rRes);
      List<Map<String, dynamic>> batches = List<Map<String, dynamic>>.from(
        bRes,
      );

      // 「hazy_1」「hazy_2」のようなバッチ連番を自動計算する魔法
      Map<int, int> recipeCounts = {};
      for (var b in batches) {
        int rId = b['recipe_id'];
        recipeCounts[rId] = (recipeCounts[rId] ?? 0) + 1;
        b['computed_batch_no'] = '${b['beer_name']}_${recipeCounts[rId]}';
      }

      // 表示用に新しい順（降順）に並び替え
      batches.sort((a, b) => b['id'].compareTo(a['id']));

      setState(() {
        _allBatches = batches;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('履歴データ取得エラー: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchBatchLogs(int batchId) async {
    setState(() => _isLoading = true);
    try {
      final logsRes = await _supabase
          .from('fermentation_logs')
          .select()
          .eq('batch_id', batchId)
          .order('log_time', ascending: true);
      setState(() {
        _currentBatchLogs = List<Map<String, dynamic>>.from(logsRes);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('ログ取得エラー: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateMemo() async {
    if (_selectedBatchId == null) return;
    try {
      await _supabase
          .from('batches')
          .update({'memo': _memoController.text})
          .eq('id', _selectedBatchId!);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('メモを保存しました！')));
      _fetchHistoryData(); // リロードして反映
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('メモ保存エラー: $e')));
    }
  }

  // --- グラフ描画ヘルパー ---
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
      height: 150,
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
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
    // フィルターされたバッチリスト
    List<Map<String, dynamic>> displayBatches = _allBatches;
    if (_selectedRecipeId != 'ALL') {
      displayBatches = displayBatches
          .where((b) => b['recipe_id'].toString() == _selectedRecipeId)
          .toList();
    }

    // 選択中のバッチデータ
    Map<String, dynamic>? activeBatch;
    if (_selectedBatchId != null) {
      activeBatch = _allBatches.firstWhere(
        (b) => b['id'] == _selectedBatchId,
        orElse: () => {},
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ==========================================
        // 左側：フィルター ＆ バッチリスト
        // ==========================================
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[100],
            child: Column(
              children: [
                // フィルター部分
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔍 レシピで絞り込み',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedRecipeId,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'ALL',
                            child: Text('すべてのレシピ'),
                          ),
                          ..._recipes
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r['id'].toString(),
                                  child: Text(r['name']),
                                ),
                              )
                              .toList(),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedRecipeId = v!),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // バッチ一覧
                Expanded(
                  child: _isLoading && _allBatches.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: displayBatches.length,
                          itemBuilder: (context, index) {
                            var b = displayBatches[index];
                            bool isSel = _selectedBatchId == b['id'];

                            // 日付フォーマット
                            String dateStr = '-';
                            if (b['brew_date'] != null) {
                              DateTime dt = DateTime.parse(
                                b['brew_date'],
                              ).toLocal();
                              dateStr = '${dt.year}/${dt.month}/${dt.day}';
                            }

                            return Container(
                              decoration: BoxDecoration(
                                color: isSel ? Colors.amber[50] : Colors.white,
                                border: const Border(
                                  bottom: BorderSide(color: Colors.black12),
                                ),
                              ),
                              child: ListTile(
                                onTap: () {
                                  setState(() {
                                    _selectedBatchId = b['id'];
                                    _memoController.text = b['memo'] ?? '';
                                  });
                                  _fetchBatchLogs(b['id']);
                                },
                                title: Text(
                                  b['computed_batch_no'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Text(
                                  '仕込日: $dateStr  |  状態: ${b['status']}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        const VerticalDivider(width: 1),

        // ==========================================
        // 右側：詳細・メモ・グラフ
        // ==========================================
        Expanded(
          flex: 5,
          child: activeBatch == null
              ? const Center(
                  child: Text(
                    '左のリストからバッチを選択してください',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 1. ヘッダー情報 ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeBatch['computed_batch_no'],
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: activeBatch['status'] == 'Completed'
                                      ? Colors.green[800]
                                      : Colors.amber[800],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  activeBatch['status'] == 'Completed'
                                      ? '完了済 (Completed)'
                                      : '発酵中 (Fermenting)',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // 数値サマリー
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                _buildStat(
                                  'OG',
                                  activeBatch['original_gravity'],
                                ),
                                const SizedBox(width: 24),
                                _buildStat('FG', activeBatch['final_gravity']),
                                const SizedBox(width: 24),
                                _buildStat(
                                  'ABV',
                                  '${activeBatch['abv'] ?? '-'} %',
                                ),
                                const SizedBox(width: 24),
                                _buildStat(
                                  '最終液量',
                                  '${activeBatch['fermenter_vol_l'] ?? '-'} L',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // --- 2. メモ欄 (Editable) ---
                      const Text(
                        '📝 バッチ・メモ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _memoController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'テイスティングノートや反省点、特記事項を入力...',
                                border: const OutlineInputBorder(),
                                fillColor: Colors.grey[50],
                                filled: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _updateMemo,
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
                      const SizedBox(height: 40),

                      // --- 3. 発酵グラフの生成 ---
                      const Text(
                        '📈 発酵曲線グラフ (Fermentation Logs)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (context) {
                          List<FlSpot> sgSpots = [];
                          List<FlSpot> tempSpots = [];
                          List<FlSpot> phSpots = [];

                          // 仕込日を基準(X=0)とする
                          DateTime? baseTime = activeBatch?['brew_date'] != null
                              ? DateTime.parse(
                                  activeBatch!['brew_date'],
                                ).toLocal()
                              : null;

                          if (baseTime != null) {
                            // 初期値
                            if (activeBatch!['original_gravity'] != null)
                              sgSpots.add(
                                FlSpot(
                                  0,
                                  (activeBatch!['original_gravity'] as num)
                                      .toDouble(),
                                ),
                              );
                            if (activeBatch!['initial_temp'] != null)
                              tempSpots.add(
                                FlSpot(
                                  0,
                                  (activeBatch!['initial_temp'] as num)
                                      .toDouble(),
                                ),
                              );
                            if (activeBatch!['initial_ph'] != null)
                              phSpots.add(
                                FlSpot(
                                  0,
                                  (activeBatch!['initial_ph'] as num)
                                      .toDouble(),
                                ),
                              );

                            // 日々のログ
                            for (var log in _currentBatchLogs) {
                              final logTime = DateTime.parse(
                                log['log_time'],
                              ).toLocal();
                              final double days =
                                  logTime.difference(baseTime).inMinutes /
                                  (60.0 * 24.0);

                              if (days >= 0) {
                                if (log['gravity'] != null)
                                  sgSpots.add(
                                    FlSpot(
                                      days,
                                      (log['gravity'] as num).toDouble(),
                                    ),
                                  );
                                if (log['temperature'] != null)
                                  tempSpots.add(
                                    FlSpot(
                                      days,
                                      (log['temperature'] as num).toDouble(),
                                    ),
                                  );
                                if (log['ph'] != null)
                                  phSpots.add(
                                    FlSpot(days, (log['ph'] as num).toDouble()),
                                  );
                              }
                            }
                          }

                          if (sgSpots.length < 2 &&
                              tempSpots.length < 2 &&
                              phSpots.length < 2) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'グラフを描画するのに十分なデータがありません。',
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }

                          return Column(
                            children: [
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
                              _buildMiniChart('pH', phSpots, Colors.teal[700]!),
                            ],
                          );
                        },
                      ),

                      // --- 4. ログ履歴テキスト ---
                      const SizedBox(height: 24),
                      const Text(
                        '🕒 詳細作業ログ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      _currentBatchLogs.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('作業ログはありません。'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _currentBatchLogs.length,
                              itemBuilder: (c, i) {
                                var log = _currentBatchLogs[i];
                                final dt = DateTime.parse(
                                  log['log_time'],
                                ).toLocal();
                                final formattedDate =
                                    '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                                return ListTile(
                                  leading: const Icon(
                                    Icons.history,
                                    color: Colors.grey,
                                  ),
                                  title: Text(
                                    log['action'] ?? '記録',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$formattedDate | Memo: ${log['memo'] ?? '-'}',
                                  ),
                                  trailing: Text(
                                    'SG:${log['gravity'] ?? '-'} / Temp:${log['temperature'] ?? '-'} / Dump:${log['dumped_vol_l'] ?? '-'}L',
                                    style: const TextStyle(
                                      color: Colors.blueGrey,
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
    );
  }

  Widget _buildStat(String label, dynamic value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.blueGrey,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value?.toString() ?? '-',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}
