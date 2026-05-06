import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class TaxTab extends StatefulWidget {
  const TaxTab({super.key});
  @override
  State<TaxTab> createState() => _TaxTabState();
}

class _TaxTabState extends State<TaxTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _taxableLogs = [];

  // 税率設定 (2026年現在の発泡酒基準)
  final Map<int, double> _taxRates = {
    1: 167.0, // 麦芽50%以上
    2: 153.0, // 麦芽25-50%
    3: 134.0, // 麦芽25%未満
  };

  final Map<int, String> _taxCategoryNames = {
    1: "麦芽50%以上",
    2: "麦芽25-50%未満",
    3: "麦芽25%未満",
  };

  @override
  void initState() {
    super.initState();
    _fetchTaxData();
  }

  Future<void> _fetchTaxData() async {
    setState(() => _isLoading = true);

    // 選択月の開始日と終了日を計算
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
      23,
      59,
      59,
    );

    try {
      // 1. 課税対象となるログ（TAP IN と MOVE）を抽出
      // 外部結合を使ってケグ情報とレシピ情報も一緒に取得する
      final response = await _supabase
          .from('keg_logs')
          .select('''
            *,
            kegs (
              keg_code,
              fill_volume,
              current_recipe,
              current_batch_id
            )
          ''')
          .filter('action', 'in', '("TAP IN", "MOVE")')
          .gte('created_at', start.toIso8601String())
          .lte('created_at', end.toIso8601String())
          .order('created_at', ascending: true);

      // 2. 各ログに対応するレシピの税率区分を紐付ける
      // (ここでは簡易的にログ内のレシピ名から税率を取得する仕組みにします)
      final List<Map<String, dynamic>> logs = List<Map<String, dynamic>>.from(
        response,
      );
      final recipeData = await _supabase
          .from('recipes')
          .select('name, tax_category');

      for (var log in logs) {
        final keg = log['kegs'];
        final recipeName = keg['current_recipe'];
        final rInfo = recipeData.firstWhere(
          (r) => r['name'] == recipeName,
          orElse: () => {'tax_category': 1},
        );
        log['tax_category'] = rInfo['tax_category'] ?? 1;
        log['volume'] = (keg['fill_volume'] ?? 0.0).toDouble();
      }

      setState(() {
        _taxableLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('酒税集計エラー: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 区分ごとの合計を計算
    Map<int, double> volumeByCat = {1: 0, 2: 0, 3: 0};
    double totalTax = 0;
    double totalVolume = 0;

    for (var log in _taxableLogs) {
      int cat = log['tax_category'];
      double vol = log['volume'];
      volumeByCat[cat] = (volumeByCat[cat] ?? 0) + vol;
      totalTax += vol * (_taxRates[cat] ?? 0);
      totalVolume += vol;
    }

    return Column(
      children: [
        // --- 上部：月選択・サマリー ---
        Container(
          padding: const EdgeInsets.all(24),
          color: Colors.white,
          child: Row(
            children: [
              Text(
                '${_selectedMonth.year}年 ${_selectedMonth.month}月分',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedMonth,
                    firstDate: DateTime(2023),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _selectedMonth = picked);
                    _fetchTaxData();
                  }
                },
                icon: const Icon(Icons.calendar_month),
                label: const Text('月を選択'),
              ),
              const Spacer(),
              _buildSummaryCard(
                '総移出数量',
                '${totalVolume.toStringAsFixed(1)} L',
                Colors.blueGrey,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                '予想納税額',
                '¥${NumberFormat('#,###').format(totalTax.toInt())}',
                Colors.amber[900]!,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // --- 中部：区分別詳細 ---
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左：区分別サマリーテーブル
                          Expanded(
                            flex: 3,
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '■ 区分別集計',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildTaxCategoryRow(1, volumeByCat[1]!),
                                    const Divider(),
                                    _buildTaxCategoryRow(2, volumeByCat[2]!),
                                    const Divider(),
                                    _buildTaxCategoryRow(3, volumeByCat[3]!),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // 右：注意書き
                          const Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                AlertBox(
                                  text:
                                      '【自家消費について】\nTAPに接続した（TAP IN）時点で課税対象（移出）となります。計測用のダンプは課税対象外ですが、この画面ではケグ単位で集計しています。',
                                ),
                                SizedBox(height: 16),
                                AlertBox(
                                  text:
                                      '【外販について】\nMOVEアクションにて外販先が選択されたものが集計されます。返品（RETURN）された場合は手動で調整が必要です。',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // --- 下部：移出明細一覧 ---
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '🕒 移出明細（課税対象ケグ一覧）',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _taxableLogs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final log = _taxableLogs[index];
                            final keg = log['kegs'];
                            final dt = DateTime.parse(
                              log['created_at'],
                            ).toLocal();
                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: log['action'] == 'TAP IN'
                                      ? Colors.orange[50]
                                      : Colors.blue[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  log['action'] == 'TAP IN'
                                      ? Icons.local_drink
                                      : Icons.local_shipping,
                                  size: 20,
                                  color: log['action'] == 'TAP IN'
                                      ? Colors.orange[900]
                                      : Colors.blue[900],
                                ),
                              ),
                              title: Text(
                                '${keg['keg_code']} - ${keg['current_recipe']} (${keg['current_batch_id']})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${DateFormat('MM/dd HH:mm').format(dt)} | ${log['detail']}',
                              ),
                              trailing: Text(
                                '${log['volume']} L',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxCategoryRow(int cat, double volume) {
    final rate = _taxRates[cat]!;
    final tax = volume * rate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _taxCategoryNames[cat]!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '単価: ¥${rate.toInt()} / L',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${volume.toStringAsFixed(1)} L',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '税額: ¥${NumberFormat('#,###').format(tax.toInt())}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber[900],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AlertBox extends StatelessWidget {
  final String text;
  const AlertBox({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        border: Border.all(color: Colors.amber[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: Colors.amber[900], height: 1.5),
      ),
    );
  }
}
