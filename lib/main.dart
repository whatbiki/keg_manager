import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'tank_data_tab.dart';
import 'recipe_master_tab.dart';
import 'inventory_tab.dart';
import 'history_tab.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://louoqnediuwsvbujoqhi.supabase.co',
    anonKey: 'sb_publishable_bLChdQpiXPUtVRciBrz55w_ynFYHzkp',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          primary: Colors.black,
        ),
      ),
      home: const KegManagerMain(),
    );
  }
}

class KegManagerMain extends StatefulWidget {
  const KegManagerMain({super.key});
  @override
  State<KegManagerMain> createState() => _KegManagerMainState();
}

class _KegManagerMainState extends State<KegManagerMain> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> supabaseKegs = [];
  List<Map<String, dynamic>> supabaseTanks = [];
  bool _isLoading = true;
  late List<String> externalLocs = ['A社'];
  Map<String, int?> tapMaster = {};

  String selectedTab = 'JOB';
  String selectedJob = 'CLEAN';
  int selectedTankId = 1;
  Set<String> selectedKegCodes = {};
  String selectedLocation = '冷蔵庫';
  String selectedCleanOption = 'AC25+ピュオロジェン';
  String selectedTapSlot = 'TAP 01';
  int? dataSelectedKegId;
  int ac3Threshold = 3;

  String registrationTag = 'A';
  String deletionTag = 'A';
  final TextEditingController _addKegCountController = TextEditingController();
  final TextEditingController _addKegSizeController = TextEditingController();
  final TextEditingController _delKegIdController = TextEditingController();
  final TextEditingController _newLocController = TextEditingController();

  String _filterTag = 'ALL';
  String _filterStatus = 'ALL';
  String _filterLocation = 'ALL';
  final TextEditingController _kegMemoC = TextEditingController();
  int? _lastSelectedKegId;

  @override
  void initState() {
    super.initState();
    for (int i = 1; i <= 8; i++) tapMaster['TAP 0$i'] = null;
    _loadData();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agartha_ext_v24', jsonEncode(externalLocs));
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    try {
      final tData = await _supabase.from('tanks').select().order('id');
      supabaseTanks = List<Map<String, dynamic>>.from(tData);

      final kData = await _supabase.from('kegs').select().order('keg_code');
      supabaseKegs = List<Map<String, dynamic>>.from(kData);

      _syncTapMaster();
    } catch (e) {
      debugPrint('データ取得エラー: $e');
    } finally {
      setState(() {
        String? ej = prefs.getString('agartha_ext_v24');
        if (ej != null) externalLocs = List<String>.from(jsonDecode(ej));
        _isLoading = false;
      });
    }
  }

  void _syncTapMaster() {
    tapMaster.updateAll((key, value) => null);
    for (var k in supabaseKegs) {
      if (k['status'] == 'TAPPED' &&
          k['location'].toString().startsWith('TAP')) {
        tapMaster[k['location']] = k['id'];
      }
    }
  }

  Future<double?> _showFillVolumeDialog() async {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('充填量 (L) を入力'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: '例: 14.5',
            suffixText: 'L',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            child: const Text('決定'),
          ),
        ],
      ),
    );
  }

  Future<int?> _showSaleDialog(String companyName) async {
    final ctrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$companyName への販売・出庫'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '販売価格 (円)',
            suffixText: '円',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, int.tryParse(ctrl.text)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            child: const Text('移出する'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ★ 追加：どこでも使える薬品希釈計算機（ダイアログ）
  // ==========================================
  void _showDilutionCalculator() {
    showDialog(
      context: context,
      builder: (context) {
        String selectedChemical = 'AC25 (アルカリ 2%)';
        final List<String> chemOptions = [
          'AC25 (アルカリ 2%)',
          'AC3 (酸 1%)',
          'Star San (1.5ml/L)',
          'ピュオロジェン (50ppm)',
          'カスタム濃度',
        ];
        final volCtrl = TextEditingController(text: '20');
        final customRatioCtrl = TextEditingController(text: '1.0');

        double reqChemicalMl = 0.0;
        double reqWaterL = 0.0;

        void calculate(void Function(void Function()) setDialogState) {
          double totalVolL = double.tryParse(volCtrl.text) ?? 0.0;
          double chemVolL = 0.0;

          if (selectedChemical == 'AC25 (アルカリ 2%)')
            chemVolL = totalVolL * 0.02;
          else if (selectedChemical == 'AC3 (酸 1%)')
            chemVolL = totalVolL * 0.01;
          else if (selectedChemical == 'Star San (1.5ml/L)')
            chemVolL = (totalVolL * 1.5) / 1000;
          else if (selectedChemical == 'ピュオロジェン (50ppm)')
            chemVolL = totalVolL * 0.001; // 5%液想定
          else if (selectedChemical == 'カスタム濃度') {
            double customPercent = double.tryParse(customRatioCtrl.text) ?? 0.0;
            chemVolL = totalVolL * (customPercent / 100);
          }

          setDialogState(() {
            reqChemicalMl = chemVolL * 1000;
            reqWaterL = totalVolL - chemVolL;
            if (reqWaterL < 0) reqWaterL = 0;
          });
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 初回計算
            if (reqChemicalMl == 0 && reqWaterL == 0) calculate(setDialogState);

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.science, color: Colors.blueGrey),
                  SizedBox(width: 8),
                  Text('薬品・洗剤 希釈計算機'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedChemical,
                      decoration: const InputDecoration(
                        labelText: '薬品の種類',
                        border: OutlineInputBorder(),
                      ),
                      items: chemOptions
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) {
                        selectedChemical = v!;
                        calculate(setDialogState);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: volCtrl,
                      decoration: const InputDecoration(
                        labelText: '作成したい総液量 (L)',
                        border: OutlineInputBorder(),
                        suffixText: 'L',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => calculate(setDialogState),
                    ),
                    if (selectedChemical == 'カスタム濃度') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: customRatioCtrl,
                        decoration: const InputDecoration(
                          labelText: '目標濃度 (%)',
                          border: OutlineInputBorder(),
                          suffixText: '%',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => calculate(setDialogState),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            '必要な原液量',
                            style: TextStyle(
                              color: Colors.blueGrey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${reqChemicalMl.toStringAsFixed(1)} ml',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.blue,
                            ),
                          ),
                          if (reqChemicalMl >= 1000)
                            Text(
                              '(= ${(reqChemicalMl / 1000).toStringAsFixed(2)} L)',
                              style: const TextStyle(color: Colors.blueGrey),
                            ),
                          const Divider(),
                          const Text(
                            '必要な水量',
                            style: TextStyle(
                              color: Colors.blueGrey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${reqWaterL.toStringAsFixed(2)} L',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red[200]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '危険: 必ず「水」に対して「薬品」を加えてください。薬品に水を加えると突沸の危険があります。',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    '閉じる',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _execute() async {
    if (selectedKegCodes.isEmpty && selectedJob != 'TAP') return;

    setState(() => _isLoading = true);

    try {
      double? inputVolume;
      int? inputPrice;
      bool isExternalMove =
          selectedJob == 'MOVE' && externalLocs.contains(selectedLocation);

      if (selectedJob == 'FILL IN') {
        inputVolume = await _showFillVolumeDialog();
        if (inputVolume == null) {
          setState(() => _isLoading = false);
          return;
        }

        for (var code in selectedKegCodes) {
          var k = supabaseKegs.firstWhere((keg) => keg['keg_code'] == code);
          double capacity = (k['capacity'] ?? 20.0).toDouble();
          if (inputVolume > capacity) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ エラー: $code (容量${capacity}L) に ${inputVolume}L は充填できません！',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      if (isExternalMove) {
        inputPrice = await _showSaleDialog(selectedLocation);
        if (inputPrice == null) {
          setState(() => _isLoading = false);
          return;
        }
      }

      if (selectedJob == 'TAP') {
        await _handleTapProcess();
      } else {
        Map<String, dynamic>? activeBatchRes;
        if (selectedJob == 'FILL IN') {
          activeBatchRes = await _supabase
              .from('batches')
              .select('id')
              .eq('tank_id', selectedTankId.toString())
              .eq('status', 'Fermenting')
              .maybeSingle();

          if (activeBatchRes == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ エラー: 選択したタンクに発酵中のバッチがありません。'),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => _isLoading = false);
            return;
          }
        }

        for (var code in selectedKegCodes) {
          var k = supabaseKegs.firstWhere((keg) => keg['keg_code'] == code);
          int internalId = k['id'];

          if (selectedJob == 'CLEAN') {
            int washCount = k['wash_count_since_acid'] ?? 0;
            if (selectedCleanOption.contains('AC3')) {
              washCount = 0;
            } else {
              washCount += 1;
            }

            await _supabase
                .from('kegs')
                .update({
                  'status': 'CLEANED',
                  'wash_count_since_acid': washCount,
                  'last_wash_type': selectedCleanOption,
                  'current_recipe': null,
                  'current_batch_id': null,
                  'location': '倉庫',
                })
                .eq('id', internalId);

            await _supabase.from('keg_logs').insert({
              'keg_id': internalId,
              'action': 'CLEAN',
              'detail': selectedCleanOption,
              'created_at': DateTime.now().toIso8601String(),
            });
          } else if (selectedJob == 'FILL IN') {
            Map<String, dynamic>? currentT;
            try {
              currentT = supabaseTanks.firstWhere(
                (t) => t['id'] == selectedTankId,
              );
            } catch (e) {}
            String recipeName = currentT?['current_recipe'] ?? '不明';
            String batchStr = currentT?['current_batch_id'] ?? '';

            String displayRecipe = batchStr.isNotEmpty
                ? '$recipeName ($batchStr)'
                : recipeName;

            await _supabase
                .from('kegs')
                .update({
                  'status': 'FILLED',
                  'current_recipe': recipeName,
                  'current_batch_id': batchStr,
                  'location': '冷蔵庫',
                  'fill_volume': inputVolume,
                  'is_tax_triggered': false,
                })
                .eq('id', internalId);

            await _supabase.from('keg_logs').insert({
              'keg_id': internalId,
              'action': 'FILL IN',
              'detail':
                  'Tank $selectedTankId -> $displayRecipe ($inputVolume L)',
              'created_at': DateTime.now().toIso8601String(),
            });
          } else if (selectedJob == 'MOVE') {
            Map<String, dynamic> updates = {'location': selectedLocation};
            if (selectedLocation == 'DISCARD') {
              updates['status'] = 'EMPTY';
              updates['current_recipe'] = null;
              updates['location'] = '倉庫';
            } else if (selectedLocation == 'RETURN') {
              updates['location'] = '冷蔵庫';
            } else if (isExternalMove) {
              updates['shipped_at'] = DateTime.now().toIso8601String();
              updates['sale_price'] = inputPrice;
              updates['is_tax_triggered'] = true;
            }

            await _supabase.from('kegs').update(updates).eq('id', internalId);
            await _supabase.from('keg_logs').insert({
              'keg_id': internalId,
              'action': 'MOVE',
              'detail': 'To $selectedLocation',
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        }

        if (selectedJob == 'FILL IN' &&
            activeBatchRes != null &&
            inputVolume != null) {
          double totalFilledVolume = inputVolume * selectedKegCodes.length;

          await _supabase.from('fermentation_logs').insert({
            'batch_id': activeBatchRes['id'],
            'log_time': DateTime.now().toIso8601String(),
            'action': 'パッケージング (${selectedKegCodes.length}樽)',
            'dumped_vol_l': totalFilledVolume,
            'memo':
                'JOBタブからの一括ケグ充填 ($inputVolume L × ${selectedKegCodes.length}本)',
          });
        }
      }

      setState(() => selectedKegCodes.clear());
      await _loadData();
    } catch (e) {
      debugPrint('JOB実行エラー: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('エラー: $e')));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleTapProcess() async {
    int? currentIdInTap = tapMaster[selectedTapSlot];

    if (currentIdInTap == null) {
      if (selectedKegCodes.length == 1) {
        var k = supabaseKegs.firstWhere(
          (k) => k['keg_code'] == selectedKegCodes.first,
        );
        int internalId = k['id'];

        await _supabase
            .from('kegs')
            .update({
              'status': 'TAPPED',
              'location': selectedTapSlot,
              'tap_in_at': DateTime.now().toIso8601String(),
              'is_tax_triggered': true,
            })
            .eq('id', internalId);

        await _supabase.from('keg_logs').insert({
          'keg_id': internalId,
          'action': 'TAP IN',
          'detail': 'Opened at $selectedTapSlot',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } else {
      await _supabase
          .from('kegs')
          .update({
            'status': 'EMPTY',
            'location': '倉庫',
            'current_recipe': null,
            'current_batch_id': null,
            'tap_out_at': DateTime.now().toIso8601String(),
          })
          .eq('id', currentIdInTap);

      await _supabase.from('keg_logs').insert({
        'keg_id': currentIdInTap,
        'action': 'TAP OUT',
        'detail': 'Empty at $selectedTapSlot',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  int _extractKegNumber(String kegCode) {
    final parts = kegCode.split('-');
    if (parts.length > 1) {
      return int.tryParse(parts.last) ?? 0;
    }
    return 0;
  }

  bool _isSelectable(Map<String, dynamic> k) {
    String st = k['status'] ?? 'EMPTY';
    if (selectedJob == 'CLEAN') return st == 'EMPTY';
    if (selectedJob == 'FILL IN') return st == 'CLEANED';
    if (selectedJob == 'MOVE') return st == 'FILLED';
    if (selectedJob == 'TAP') {
      return st == 'FILLED' &&
          k['location'] == '冷蔵庫' &&
          tapMaster[selectedTapSlot] == null;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF9F1F0),
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }
    return Scaffold(
      // ★ 追加: 画面右下に浮かぶ計算機ボタン！
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.amber,
        onPressed: _showDilutionCalculator,
        child: const Icon(Icons.calculate, color: Colors.black, size: 28),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopHeader(),
            const Divider(thickness: 2, height: 1, color: Colors.black),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'BREW WORKS MANAGER',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          Row(
            children: [
              'JOB',
              'DATA',
              'SET',
              'INVENTORY',
            ].map((t) => _tabNav(t)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _tabNav(String t) => TextButton(
    onPressed: () => setState(() => selectedTab = t),
    child: Text(
      t,
      style: TextStyle(
        color: selectedTab == t ? Colors.black : Colors.grey,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
    ),
  );

  Widget _buildBody() {
    if (selectedTab == 'DATA') return _buildDataTabWrapper();
    if (selectedTab == 'SET') return _buildSetWrapper();
    if (selectedTab == 'INVENTORY') return const InventoryTab();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildJobTab(),
    );
  }

  Widget _buildDataTabWrapper() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: Colors.black87,
            child: const TabBar(
              indicatorColor: Colors.amber,
              labelColor: Colors.amber,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(icon: Icon(Icons.science), text: 'TANK (現在)'),
                Tab(icon: Icon(Icons.kitchen), text: 'KEG (在庫)'),
                Tab(icon: Icon(Icons.history), text: 'HISTORY (履歴)'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                const TankDataTab(),
                _buildDataTab(),
                const HistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetWrapper() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.black87,
            child: const TabBar(
              indicatorColor: Colors.amber,
              labelColor: Colors.amber,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(icon: Icon(Icons.menu_book), text: 'RECIPE (液種管理)'),
                Tab(icon: Icon(Icons.settings), text: 'SYSTEM (ケグ・設定)'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [const RecipeMasterTab(), _buildSetTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 50,
              child: Text('JOB', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    'CLEAN',
                    'FILL IN',
                    'MOVE',
                    'TAP',
                  ].map((j) => _jobBtn(j)).toList(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (selectedJob == 'FILL IN') ...[
          Row(
            children: [
              const SizedBox(width: 50, child: Text('TANK')),
              for (int i = 1; i <= 4; i++)
                _sqBtn(i.toString(), selectedTankId == i, () {
                  setState(() {
                    selectedTankId = i;
                    selectedJob = 'FILL IN';
                  });
                }),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 50, top: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Builder(
                builder: (context) {
                  Map<String, dynamic>? currentTank;
                  try {
                    currentTank = supabaseTanks.firstWhere(
                      (t) => t['id'] == selectedTankId,
                    );
                  } catch (e) {}
                  String displayRecipe =
                      currentTank?['current_recipe'] ?? 'Empty (空です)';
                  String displayBatch = currentTank?['current_batch_id'] != null
                      ? ' (${currentTank!['current_batch_id']})'
                      : '';
                  return Text(
                    '$displayRecipe $displayBatch',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
          ),
        ],

        if (selectedJob == 'TAP') ...[
          const Text(
            'SELECT TAP SLOT',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Wrap(
            spacing: 4,
            children: [
              for (int i = 1; i <= 8; i++) "TAP 0$i",
            ].map((t) => _locBtn(t, isTap: true)).toList(),
          ),
          const SizedBox(height: 10),
        ],
        const Text('KEG GRID', style: TextStyle(fontWeight: FontWeight.bold)),
        _buildKegGrid(),

        if (selectedJob == 'MOVE' && selectedKegCodes.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'MOVE TO LOCATION',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 5,
            children: [
              '冷蔵庫',
              'DISCARD',
              'RETURN',
              ...externalLocs,
            ].map((l) => _locBtn(l)).toList(),
          ),
        ],
        const SizedBox(height: 20),
        _buildWorkspace(),
      ],
    );
  }

  Widget _buildKegGrid() {
    if (supabaseKegs.isEmpty)
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No Kegs Registered."),
        ),
      );

    var aKegs = supabaseKegs
        .where((k) => k['keg_code'].toString().startsWith('A'))
        .toList();
    aKegs.sort(
      (a, b) => _extractKegNumber(
        a['keg_code'],
      ).compareTo(_extractKegNumber(b['keg_code'])),
    );

    var oKegs = supabaseKegs
        .where((k) => k['keg_code'].toString().startsWith('O'))
        .toList();
    oKegs.sort(
      (a, b) => _extractKegNumber(
        a['keg_code'],
      ).compareTo(_extractKegNumber(b['keg_code'])),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (aKegs.isNotEmpty) ...[
          const Text(
            "TAG-A (自社用 SUS)",
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          _gridPart(aKegs),
        ],
        const SizedBox(height: 8),
        if (oKegs.isNotEmpty) ...[
          const Text(
            "TAG-O (ワンウェイ PET)",
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          _gridPart(oKegs),
        ],
      ],
    );
  }

  Widget _gridPart(List<Map<String, dynamic>> list) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 10,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.5,
      ),
      itemCount: list.length,
      itemBuilder: (c, i) {
        var k = list[i];
        String kCode = k['keg_code'];
        bool isS = selectedKegCodes.contains(kCode);
        bool canS = _isSelectable(k);
        Color bg = isS
            ? Colors.black
            : (canS
                  ? (k['status'] == 'CLEANED'
                        ? Colors.green[50]!
                        : (k['status'] == 'FILLED'
                              ? Colors.blueGrey[100]!
                              : Colors.white))
                  : Colors.grey[300]!);
        return GestureDetector(
          onTap: canS
              ? () => setState(() {
                  if (selectedJob == 'TAP') selectedKegCodes.clear();
                  isS
                      ? selectedKegCodes.remove(kCode)
                      : selectedKegCodes.add(kCode);
                })
              : null,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              color: bg,
            ),
            child: Center(
              child: Text(
                kCode,
                style: TextStyle(
                  color: isS
                      ? Colors.white
                      : (canS ? Colors.black : Colors.black38),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkspace() {
    List<String> ac3Alerts = [];
    if (selectedJob == 'CLEAN') {
      for (var code in selectedKegCodes) {
        var k = supabaseKegs.firstWhere((k) => k['keg_code'] == code);
        int wc = k['wash_count_since_acid'] ?? 0;
        if (wc >= ac3Threshold && code.startsWith('A')) ac3Alerts.add(code);
      }
    }
    String btnText =
        (selectedJob == 'TAP' && tapMaster[selectedTapSlot] != null)
        ? "TAP OUT"
        : "SET (実行)";
    Color btnColor =
        (selectedJob == 'TAP' && tapMaster[selectedTapSlot] != null)
        ? Colors.red[700]!
        : Colors.amber[700]!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ac3Alerts.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(bottom: 10),
              width: double.infinity,
              child: Text(
                "⚠️ AC3(酸洗浄)推奨: ${ac3Alerts.join(', ')}",
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                color: Colors.black,
                child: Text(
                  selectedJob,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnColor,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                onPressed: _execute,
                child: Text(
                  btnText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildWorkspaceContent(),
        ],
      ),
    );
  }

  Widget _buildWorkspaceContent() {
    if (selectedJob == 'CLEAN') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoBox('KEG', '${selectedKegCodes.length}', 'selected'),
          const Text(
            'DO',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Column(
            children: ['AC25+ピュオロジェン', 'AC25+AC3+ピュオロジェン']
                .map(
                  (o) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: _choiceBtn(o),
                  ),
                )
                .toList(),
          ),
        ],
      );
    }
    if (selectedJob == 'FILL IN') {
      String recipeName = 'Empty';
      try {
        final t = supabaseTanks.firstWhere((t) => t['id'] == selectedTankId);
        recipeName = t['current_recipe'] ?? 'Empty';
      } catch (e) {}
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoBox('TANK', '$selectedTankId', recipeName),
          const Text(
            'TO',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          _infoBox('KEGS', '${selectedKegCodes.length}', 'selected'),
        ],
      );
    }
    if (selectedJob == 'MOVE') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoBox('KEGS', '${selectedKegCodes.length}', 'selected'),
          const Text(
            'TO',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          _infoBox('LOC', selectedLocation, 'Destination'),
        ],
      );
    }
    if (selectedJob == 'TAP') {
      int? currentId = tapMaster[selectedTapSlot];
      String kegDisp = currentId != null
          ? supabaseKegs.firstWhere((k) => k['id'] == currentId)['keg_code']
          : (selectedKegCodes.isEmpty ? '?' : selectedKegCodes.first);
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoBox('KEG', kegDisp, 'Tap Action'),
          const Text(
            'TO',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          _infoBox('TAP', selectedTapSlot, '-'),
        ],
      );
    }
    return const SizedBox();
  }

  Widget _infoBox(String t, String v, String s) => Column(
    children: [
      Text(t, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      Text(
        v,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      Text(
        s,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    ],
  );

  Widget _choiceBtn(String l) {
    bool s = selectedCleanOption == l;
    return GestureDetector(
      onTap: () => setState(() => selectedCleanOption = l),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black),
          color: s ? Colors.black : Colors.white,
        ),
        child: Text(
          l,
          style: TextStyle(
            color: s ? Colors.white : Colors.black,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildDataTab() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: _buildFilterPane(),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(flex: 3, child: _buildFilteredKegList()),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 5,
          child: dataSelectedKegId == null
              ? const Center(
                  child: Text(
                    'リストからケグを選択してください',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _buildKegDetailPane(),
        ),
      ],
    );
  }

  Widget _buildFilterPane() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔍 絞り込み',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Divider(),
          const SizedBox(height: 8),

          const Text(
            '■ 記号 (TAG)',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: ['ALL', 'A', 'O']
                .map(
                  (t) => ChoiceChip(
                    label: Text(t),
                    selected: _filterTag == t,
                    onSelected: (s) => setState(() => _filterTag = t),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),

          const Text(
            '■ 状態 (STATUS)',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: ['ALL', 'EMPTY', 'CLEANED', 'FILLED', 'TAPPED']
                .map(
                  (t) => ChoiceChip(
                    label: Text(t),
                    selected: _filterStatus == t,
                    onSelected: (s) => setState(() => _filterStatus = t),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),

          const Text(
            '■ 場所 (LOCATION)',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: ['ALL', '倉庫', '冷蔵庫', 'TAP', '客先(外販)']
                .map(
                  (t) => ChoiceChip(
                    label: Text(t),
                    selected: _filterLocation == t,
                    onSelected: (s) => setState(() => _filterLocation = t),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredKegList() {
    List<Map<String, dynamic>> filtered = supabaseKegs.where((k) {
      if (_filterTag != 'ALL' &&
          !k['keg_code'].toString().startsWith(_filterTag))
        return false;
      if (_filterStatus != 'ALL' && k['status'] != _filterStatus) return false;
      if (_filterLocation != 'ALL') {
        String loc = k['location'] ?? '';
        if (_filterLocation == 'TAP' && !loc.startsWith('TAP')) return false;
        if (_filterLocation == '客先(外販)' && !externalLocs.contains(loc))
          return false;
        if (_filterLocation == '倉庫' && loc != '倉庫') return false;
        if (_filterLocation == '冷蔵庫' && loc != '冷蔵庫') return false;
      }
      return true;
    }).toList();

    filtered.sort(
      (a, b) => _extractKegNumber(
        a['keg_code'],
      ).compareTo(_extractKegNumber(b['keg_code'])),
    );

    if (filtered.isEmpty) {
      return const Center(
        child: Text('該当するケグがありません', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (c, i) {
        var k = filtered[i];
        bool isSel = dataSelectedKegId == k['id'];

        String batch = k['current_batch_id'] != null
            ? ' (${k['current_batch_id']})'
            : '';
        String recipe = k['current_recipe'] != null
            ? '${k['current_recipe']}$batch'
            : '-';

        return ListTile(
          selected: isSel,
          selectedTileColor: Colors.amber[50],
          onTap: () => setState(() {
            dataSelectedKegId = k['id'];
            if (_lastSelectedKegId != k['id']) {
              _kegMemoC.text = k['memo'] ?? '';
              _lastSelectedKegId = k['id'];
            }
          }),
          title: Text(
            '${k['keg_code']} [${k['status']}]',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '場所: ${k['location'] ?? '倉庫'} \n液名: $recipe',
            style: const TextStyle(fontSize: 12),
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        );
      },
    );
  }

  Widget _buildKegDetailPane() {
    var k = supabaseKegs.firstWhere(
      (keg) => keg['id'] == dataSelectedKegId,
      orElse: () => {},
    );
    if (k.isEmpty) return const SizedBox();

    String batch = k['current_batch_id'] != null
        ? ' (${k['current_batch_id']})'
        : '';
    String recipe = k['current_recipe'] != null
        ? '${k['current_recipe']}$batch'
        : '-';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${k['keg_code']}  [${k['status']}]',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  k['location'] ?? '倉庫',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '液名: $recipe',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '洗浄回数: ${k['wash_count_since_acid'] ?? 0} 回',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          const Divider(thickness: 2),
          const SizedBox(height: 8),

          const Text(
            '📝 メモ (Memo)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kegMemoC,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'タップの状態や返却予定などを入力...',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  await _supabase
                      .from('kegs')
                      .update({'memo': _kegMemoC.text})
                      .eq('id', k['id']);
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('メモを保存しました')));
                  _loadData();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('SAVE'),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(thickness: 2),
          const SizedBox(height: 8),
          const Text(
            '🕒 履歴 (History)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _supabase
                  .from('keg_logs')
                  .select()
                  .eq('keg_id', k['id'])
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                var logs = snapshot.data!;
                if (logs.isEmpty)
                  return const Center(
                    child: Text(
                      'まだ履歴がありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );

                return ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    var log = logs[i];
                    final dt = DateTime.parse(log['created_at']).toLocal();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(
                        '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            color: Colors.black,
                            child: Text(
                              log['action'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              log['detail'] ?? '',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'KEG REGISTRATION (クラウドへ登録)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _tagBtn(
              registrationTag,
              'A',
              (t) => setState(() => registrationTag = t),
            ),
            _tagBtn(
              registrationTag,
              'O',
              (t) => setState(() => registrationTag = t),
            ),
            Expanded(
              child: TextField(
                controller: _addKegCountController,
                decoration: const InputDecoration(labelText: '追加本数 (Qty)'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _addKegSizeController,
                decoration: const InputDecoration(
                  labelText: 'サイズ (L)',
                  hintText: '20',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                int count = int.tryParse(_addKegCountController.text) ?? 0;
                double capacity =
                    double.tryParse(_addKegSizeController.text) ?? 20.0;
                String size = "${capacity.toInt()}L";

                if (count <= 0) return;
                setState(() => _isLoading = true);

                try {
                  var currentTagKegs = supabaseKegs
                      .where(
                        (k) => k['keg_code'].toString().startsWith(
                          registrationTag,
                        ),
                      )
                      .toList();
                  int startNum = 1;
                  if (currentTagKegs.isNotEmpty) {
                    List<int> nums = currentTagKegs
                        .map((k) => _extractKegNumber(k['keg_code'].toString()))
                        .toList();
                    startNum = nums.reduce((a, b) => a > b ? a : b) + 1;
                  }

                  String initialStatus = registrationTag == 'O'
                      ? 'CLEANED'
                      : 'EMPTY';

                  for (int i = 0; i < count; i++) {
                    await _supabase.from('kegs').insert({
                      'keg_code': '$registrationTag-${startNum + i}',
                      'keg_type': size,
                      'capacity': capacity,
                      'status': initialStatus,
                      'location': '倉庫',
                    });
                  }
                  _addKegCountController.clear();
                  await _loadData();
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$count本のケグを登録しました')));
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('エラー: $e')));
                  setState(() => _isLoading = false);
                }
              },
              child: const Text("ADD KEGS"),
            ),
          ],
        ),

        const Divider(height: 40),
        const Text(
          'DELETE KEG (クラウドから削除)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _tagBtn(deletionTag, 'A', (t) => setState(() => deletionTag = t)),
            _tagBtn(deletionTag, 'O', (t) => setState(() => deletionTag = t)),
            Expanded(
              child: TextField(
                controller: _delKegIdController,
                decoration: const InputDecoration(labelText: '削除する番号 (例: 1)'),
                keyboardType: TextInputType.number,
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                int? num = int.tryParse(_delKegIdController.text);
                if (num == null) return;
                String targetCode = "$deletionTag-$num";

                setState(() => _isLoading = true);
                try {
                  await _supabase
                      .from('kegs')
                      .delete()
                      .eq('keg_code', targetCode);
                  _delKegIdController.clear();
                  await _loadData();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$targetCode を完全に削除しました')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('削除エラー: $e')));
                  setState(() => _isLoading = false);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50]),
              child: const Text(
                "DELETE",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        const Divider(height: 40),
        const Text(
          'LOCATION & RULES',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newLocController,
                decoration: const InputDecoration(
                  labelText: 'New Location (外販先など)',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (_newLocController.text.isNotEmpty) {
                  setState(() => externalLocs.add(_newLocController.text));
                  _saveSettings();
                  _newLocController.clear();
                }
              },
              child: const Text("CREATE"),
            ),
          ],
        ),
        Wrap(
          spacing: 5,
          children: externalLocs
              .map(
                (l) => Chip(
                  label: Text(l),
                  onDeleted: () {
                    setState(() => externalLocs.remove(l));
                    _saveSettings();
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _tagBtn(String current, String target, Function(String) onSet) {
    bool s = current == target;
    return GestureDetector(
      onTap: () => onSet(target),
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black),
          color: s ? Colors.black : Colors.white,
        ),
        child: Center(
          child: Text(
            target,
            style: TextStyle(
              color: s ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _jobBtn(String l) {
    bool s = selectedJob == l;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: s ? Colors.black : Colors.white,
          foregroundColor: s ? Colors.white : Colors.black,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: () => setState(() {
          selectedJob = l;
          selectedKegCodes.clear();
        }),
        child: Text(l, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _locBtn(String l, {bool isTap = false}) {
    bool s = (isTap ? selectedTapSlot == l : selectedLocation == l);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: s ? Colors.black : Colors.white,
        foregroundColor: s ? Colors.white : Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      onPressed: () => setState(() {
        if (isTap) {
          selectedTapSlot = l;
          selectedJob = 'TAP';
          selectedKegCodes.clear();
        } else {
          selectedLocation = l;
        }
      }),
      child: Text(l, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _sqBtn(String t, bool s, VoidCallback o) => GestureDetector(
    onTap: o,
    child: Container(
      width: 45,
      height: 35,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 2),
        color: s ? Colors.black : Colors.white,
      ),
      child: Center(
        child: Text(
          t,
          style: TextStyle(
            color: s ? Colors.white : Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ),
  );
}
