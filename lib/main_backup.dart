import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'keg_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://louoqnediuwsvbujoqhi.supabase.co',
    anonKey: 'sb_publishable_bLChdQpiXPUtVRciBrz55w_ynFYHzkp',
  );

  runApp(const AgarthaApp());
}

// --- モデル類 ---
class KegLog {
  final DateTime timestamp;
  final String action;
  final String detail;
  final String? memo;
  final String prevStatus;
  final String prevContents;
  final String prevLocation;

  KegLog({
    required this.timestamp,
    required this.action,
    required this.detail,
    this.memo,
    this.prevStatus = 'EMPTY',
    this.prevContents = '-',
    this.prevLocation = '倉庫',
  });

  Map<String, dynamic> toJson() => {
    't': timestamp.toIso8601String(),
    'a': action,
    'd': detail,
    'm': memo,
    'ps': prevStatus,
    'pc': prevContents,
    'pl': prevLocation,
  };

  factory KegLog.fromJson(Map<String, dynamic> json) => KegLog(
    timestamp: DateTime.parse(json['t']),
    action: json['a'],
    detail: json['d'],
    memo: json['m'],
    prevStatus: json['ps'] ?? 'EMPTY',
    prevContents: json['pc'] ?? '-',
    prevLocation: json['pl'] ?? '倉庫',
  );
}

class Keg {
  String tag;
  int number;
  String status;
  int ac25Count;
  String contents;
  String date;
  String location;
  String size;
  String currentMemo;

  // ★ NEW: 充填量、税金、販売管理用のプロパティを追加！
  double? fillVolume;
  DateTime? tapInAt;
  DateTime? tapOutAt;
  DateTime? shippedAt;
  int? salePrice;
  bool isTaxTriggered;

  List<KegLog> history;

  String get id => "$tag-$number";

  Keg({
    required this.tag,
    required this.number,
    this.status = 'EMPTY',
    this.ac25Count = 0,
    this.contents = '-',
    this.date = '-',
    this.location = '倉庫',
    this.size = '20L',
    this.currentMemo = '',
    this.fillVolume,
    this.tapInAt,
    this.tapOutAt,
    this.shippedAt,
    this.salePrice,
    this.isTaxTriggered = false,
  }) : history = [];

  void addLog(String action, String detail, {String? memo}) {
    history.insert(
      0,
      KegLog(
        timestamp: DateTime.now(),
        action: action,
        detail: detail,
        memo: memo,
        prevStatus: status,
        prevContents: contents,
        prevLocation: location,
      ),
    );
  }

  // ローカル保存用（SharedPreferences用）
  Map<String, dynamic> toJson() => {
    'tg': tag,
    'n': number,
    's': status,
    'c': ac25Count,
    'con': contents,
    'd': date,
    'l': location,
    'sz': size,
    'm': currentMemo,
    'fv': fillVolume,
    'ti': tapInAt?.toIso8601String(),
    'to': tapOutAt?.toIso8601String(),
    'sh': shippedAt?.toIso8601String(),
    'sp': salePrice,
    'tax': isTaxTriggered,
    'h': history.map((e) => e.toJson()).toList(),
  };

  factory Keg.fromJson(Map<String, dynamic> json) {
    var k = Keg(
      tag: json['tg'] ?? 'A',
      number: json['n'] ?? 0,
      status: json['s'] ?? 'EMPTY',
      ac25Count: json['c'] ?? 0,
      contents: json['con'] ?? '-',
      date: json['d'] ?? '-',
      location: json['l'] ?? '倉庫',
      size: json['sz'] ?? '20L',
      currentMemo: json['m'] ?? '',
      fillVolume: json['fv'],
      tapInAt: json['ti'] != null ? DateTime.parse(json['ti']) : null,
      tapOutAt: json['to'] != null ? DateTime.parse(json['to']) : null,
      shippedAt: json['sh'] != null ? DateTime.parse(json['sh']) : null,
      salePrice: json['sp'],
      isTaxTriggered: json['tax'] ?? false,
    );
    if (json['h'] != null) {
      k.history = (json['h'] as List).map((e) => KegLog.fromJson(e)).toList();
    }
    return k;
  }
}

class Tank {
  int id;
  String beerName;
  String brewDate;
  Tank({required this.id, this.beerName = '-', this.brewDate = '-'});
  Map<String, dynamic> toJson() => {'id': id, 'n': beerName, 'd': brewDate};
  factory Tank.fromJson(Map<String, dynamic> json) =>
      Tank(id: json['id'], beerName: json['n'], brewDate: json['d']);
}

class AgarthaApp extends StatelessWidget {
  const AgarthaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF9F1F0),
        primaryColor: Colors.black,
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
  // ★ Supabaseのクライアントを追加
  final _supabase = Supabase.instance.client;

  late List<Keg> allKegs = [];
  // late List<Tank> allTanks = []; // ← これは消します！
  List<Map<String, dynamic>> supabaseTanks = []; // ★ 代わりにこれを使います

  late List<String> externalLocs = ['A社'];
  Map<String, String?> tapMaster = {};

  String selectedTab = 'JOB';
  String selectedJob = 'CLEAN';
  int selectedTankId = 1;
  Set<String> selectedKegIds = {};
  String selectedLocation = '冷蔵庫';
  String selectedCleanOption = 'AC25+ピュオロジェン';
  String selectedTapSlot = 'TAP 01';
  String? dataSelectedKegId;
  int ac3Threshold = 4;

  String registrationTag = 'A';
  String deletionTag = 'A';
  final TextEditingController _beerNameController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _ac3Controller = TextEditingController();
  final TextEditingController _addKegCountController = TextEditingController();
  final TextEditingController _addKegSizeController = TextEditingController();
  final TextEditingController _delKegIdController = TextEditingController();
  final TextEditingController _newLocController = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (int i = 1; i <= 8; i++) {
      tapMaster['TAP 0$i'] = null;
    }
    _loadData();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'agartha_final_v23',
      jsonEncode(allKegs.map((e) => e.toJson()).toList()),
    );

    // ★ 削除: allTanks をローカル保存する処理はもう不要なので消しました！

    await prefs.setString('agartha_ext_v23', jsonEncode(externalLocs));
    await prefs.setInt(
      'agartha_ac3_v23',
      ac3Threshold,
    ); // ※おまけ：ここの末尾のセミコロン(;)も足しておきました！
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // ★ NEW: Supabaseからリアルなタンクデータを引っ張ってくる！
    try {
      final data = await _supabase.from('tanks').select().order('id');
      supabaseTanks = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Supabaseタンク取得エラー: $e');
    }

    setState(() {
      ac3Threshold = prefs.getInt('agartha_ac3_v23') ?? 4;
      _ac3Controller.text = ac3Threshold.toString();

      String? kj = prefs.getString('agartha_final_v23');
      String? ej = prefs.getString('agartha_ext_v23');

      allKegs = kj != null
          ? (jsonDecode(kj) as List).map((e) => Keg.fromJson(e)).toList()
          : [];
      if (ej != null) externalLocs = List<String>.from(jsonDecode(ej));

      _syncTapMaster();
    });
  }

  void _syncTapMaster() {
    tapMaster.updateAll((key, value) => null);
    for (var k in allKegs) {
      if (k.status == 'TAPPED' && k.location.startsWith('TAP')) {
        tapMaster[k.location] = k.id;
      }
    }
  }

  void _updateControllers() {
    // TANK_EDITは廃止し、Supabaseのリアルタイムデータを使うため、ここは空にします
  }

  // ★ NEW: FILL IN 時に充填量を入力させるダイアログ
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

  // ★ NEW: 外販 (MOVE) 時に販売価格を入力させるダイアログ
  Future<int?> _showSaleDialog(String companyName) async {
    final ctrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$companyName への移出・販売'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '販売価格 (円)',
            hintText: '例: 12000',
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

  // ★ 修正版：すべての赤線を消すための完全な _execute と TAP処理の塊
  Future<void> _execute() async {
    // 1. ダイアログ入力
    double? inputVolume;
    if (selectedJob == 'FILL IN' && selectedKegIds.isNotEmpty) {
      inputVolume = await _showFillVolumeDialog();
      if (inputVolume == null) return;
    }

    int? inputPrice;
    bool isExternalMove =
        selectedJob == 'MOVE' && externalLocs.contains(selectedLocation);
    if (isExternalMove && selectedKegIds.isNotEmpty) {
      inputPrice = await _showSaleDialog(selectedLocation);
      if (inputPrice == null) return;
    }

    // 2. データ更新
    if (selectedJob == 'TAP') {
      _handleTapProcess();
    } else {
      for (var id in selectedKegIds) {
        int idx = allKegs.indexWhere((k) => k.id == id);
        if (idx == -1) continue;
        var k = allKegs[idx];

        if (selectedJob == 'MEMO') {
          k.addLog('MEMO', 'User Memo', memo: _memoController.text);
          k.currentMemo = _memoController.text;
        } else if (selectedJob == 'CLEAN') {
          k.addLog('CLEAN', selectedCleanOption);
          k.status = 'CLEANED';
          if (selectedCleanOption.contains('AC3')) {
            k.ac25Count = 0;
          } else {
            k.ac25Count++;
          }
          k.contents = '-';
          k.date = '-';
        } else if (selectedJob == 'FILL IN') {
          Map<String, dynamic>? currentT;
          try {
            currentT = supabaseTanks.firstWhere(
              (t) => t['id'] == selectedTankId,
            );
          } catch (e) {}

          String recipeName = currentT?['current_recipe'] ?? '不明なビール';
          String dateStr = currentT?['start_time'] != null
              ? DateFormat(
                  'yyyy/MM/dd',
                ).format(DateTime.parse(currentT!['start_time']).toLocal())
              : '-';

          k.addLog(
            'FILL IN',
            'Tank $selectedTankId -> $recipeName ($inputVolume L)',
          );
          k.status = 'FILLED';
          k.contents = recipeName;
          k.date = dateStr;
          k.location = '冷蔵庫';
          k.fillVolume = inputVolume;
          k.isTaxTriggered = false;

          if (currentT != null && inputVolume != null) {
            double beforeVol = (currentT['volume'] ?? 0.0).toDouble();
            await _supabase
                .from('tanks')
                .update({'volume': beforeVol - inputVolume})
                .eq('id', selectedTankId);
            await _supabase.from('tank_logs').insert({
              'tank_id': selectedTankId,
              'recipe_name': recipeName,
              'batch_id': currentT['current_batch_id'],
              'batch_number': currentT['current_batch_number'],
              'log_type': 'TRANSFER',
              'amount_changed': inputVolume,
              'action': '🚚 ケグ詰め: ${k.id} ($inputVolume L)',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        } else if (selectedJob == 'MOVE') {
          k.addLog('MOVE', 'To $selectedLocation');
          if (selectedLocation == 'DISCARD') {
            k.status = 'EMPTY';
            k.contents = '-';
            k.location = '倉庫';
          } else if (selectedLocation == 'RETURN') {
            k.location = '冷蔵庫';
          } else {
            k.location = selectedLocation;
            if (externalLocs.contains(selectedLocation)) {
              k.shippedAt = DateTime.now();
              k.salePrice = inputPrice;
              k.isTaxTriggered = true;
            }
          }
        }
      }
    }

    // 3. 画面リフレッシュと保存
    setState(() {
      if (selectedJob == 'MEMO') _memoController.clear();
      selectedKegIds.clear();
    });

    await _saveData();
    await _loadData();
  }

  // ★ TAPの処理（独立した関数）
  void _handleTapProcess() {
    setState(() {
      String? currentKegIdInTap = tapMaster[selectedTapSlot];
      if (currentKegIdInTap == null) {
        if (selectedKegIds.length == 1) {
          String newId = selectedKegIds.first;
          int idx = allKegs.indexWhere((k) => k.id == newId);
          allKegs[idx].addLog('TAP IN', 'Opened at $selectedTapSlot');
          allKegs[idx].location = selectedTapSlot;
          allKegs[idx].status = 'TAPPED';
          allKegs[idx].tapInAt = DateTime.now();
          allKegs[idx].isTaxTriggered = true;
          tapMaster[selectedTapSlot] = newId;
        }
      } else {
        int idx = allKegs.indexWhere((k) => k.id == currentKegIdInTap);
        if (idx != -1) {
          allKegs[idx].addLog('TAP OUT', 'Empty at $selectedTapSlot');
          allKegs[idx].status = 'EMPTY';
          allKegs[idx].location = '倉庫';
          allKegs[idx].contents = '-';
          allKegs[idx].tapOutAt = DateTime.now();
        }
        tapMaster[selectedTapSlot] = null;
      }
      selectedKegIds.clear();
      _saveData();
    });
  }

  // ★ 後戻り（Undo）機能
  void _undoLatestHistory(Keg k) {
    if (k.history.isEmpty) return;
    setState(() {
      KegLog latest = k.history.removeAt(0);
      k.status = latest.prevStatus;
      k.contents = latest.prevContents;
      k.location = latest.prevLocation;

      if (latest.action == 'CLEAN') {
        if (latest.detail.contains('AC3')) {
          k.ac25Count = ac3Threshold;
        } else if (k.ac25Count > 0) {
          k.ac25Count--;
        }
      } else if (latest.action == 'FILL IN') {
        k.fillVolume = null;
        k.isTaxTriggered = false;
      } else if (latest.action == 'TAP IN') {
        k.tapInAt = null;
        k.isTaxTriggered = false;
      } else if (latest.action == 'TAP OUT') {
        k.tapOutAt = null;
      } else if (latest.action == 'MOVE' && latest.detail.contains('To')) {
        k.shippedAt = null;
        k.salePrice = null;
        k.isTaxTriggered = false;
      }
      _syncTapMaster();
      _saveData();
    });
  }

  bool _isSelectable(Keg k) {
    if (selectedJob == 'CLEAN') return k.status == 'EMPTY';
    if (selectedJob == 'FILL IN') return k.status == 'CLEANED';
    if (selectedJob == 'MOVE') return (k.status == 'FILLED');
    if (selectedJob == 'TAP') {
      return k.status == 'FILLED' &&
          k.location == '冷蔵庫' &&
          tapMaster[selectedTapSlot] == null;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            'BREW WORKS MANAGEMER',
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
    // --- 新追加：DATAタブの中を3つに分けるラッパー ---
    Widget _buildDataTabWrapper() {
      return DefaultTabController(
        length: 3, // ★ 2から3に変更！
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
                  Tab(icon: Icon(Icons.history), text: 'HISTORY (過去)'), // ★ 追加！
                  Tab(icon: Icon(Icons.kitchen), text: 'KEG (在庫)'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const TankDataTab(), // TANK画面
                  const HistoryTab(), // ★ これから作るHISTORY画面
                  _buildDataTab(), // KEG画面
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (selectedTab == 'DATA') return _buildDataTabWrapper();
    if (selectedTab == 'SET') return _buildSetWrapper();
    if (selectedTab == 'INVENTORY') return const InventoryTab();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildJobTab(),
    );
  }

  // --- 新追加：SETタブの中をさらに2つの画面に分ける仕組み ---
  Widget _buildSetWrapper() {
    return DefaultTabController(
      length: 2, // タブの数
      child: Column(
        children: [
          // 上部の切り替えボタン（黒と黄色で統一！）
          Container(
            color: Colors.black87,
            child: const TabBar(
              indicatorColor: Colors.amber,
              labelColor: Colors.amber,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(icon: Icon(Icons.science), text: 'RECIPE (液種管理)'),
                Tab(icon: Icon(Icons.settings), text: 'SYSTEM (ケグ・設定)'),
              ],
            ),
          ),
          // 選んだタブの中身を表示するエリア
          Expanded(
            child: TabBarView(
              children: [
                const RecipeMasterTab(), // 新しく作ったレシピ画面
                _buildSetTab(), // ★先ほど見せていただいた昔の設定画面！（_buildSetTab という名前ならアンダーバーをつけてください）
              ],
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
            const SizedBox(width: 50, child: Text('JOB')),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    'CLEAN',
                    'FILL IN',
                    'MOVE',
                    'TAP',
                    'MEMO',
                  ].map((j) => _jobBtn(j)).toList(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ★ UPDATE: EDITボタンを削除し、Supabaseのデータを表示
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
                  if (supabaseTanks.isNotEmpty) {
                    try {
                      currentTank = supabaseTanks.firstWhere(
                        (t) => t['id'] == selectedTankId,
                      );
                    } catch (e) {}
                  }

                  String displayRecipe =
                      currentTank?['current_recipe'] ?? 'Empty (空です)';
                  String displayBatch =
                      currentTank?['current_batch_number'] != null
                      ? '_${currentTank!['current_batch_number']}'
                      : '';
                  String displayDate = currentTank?['start_time'] != null
                      ? DateFormat('yyyy/MM/dd').format(
                          DateTime.parse(currentTank!['start_time']).toLocal(),
                        )
                      : '-';

                  return Text(
                    '$displayRecipe $displayBatch  $displayDate',
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

        if (selectedJob == 'MOVE' && selectedKegIds.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'SELECTED KEGS DETAILS',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Container(
            width: double.infinity,
            height: 120,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              color: Colors.white,
            ),
            child: SingleChildScrollView(
              child: Text(
                _getSelectedKegsDetails(),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ],
        if (selectedJob == 'MOVE') ...[
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

  String _getSelectedKegsDetails() {
    List<String> sortedIds = selectedKegIds.toList()..sort();
    return sortedIds
        .map((id) {
          var k = allKegs.firstWhere((keg) => keg.id == id);
          return '${k.id}: ${k.contents} (@${k.location})';
        })
        .join('  /  ');
  }

  Widget _buildKegGrid() {
    if (allKegs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No Kegs Registered."),
        ),
      );
    }
    var aKegs = allKegs.where((k) => k.tag == 'A').toList();
    var oKegs = allKegs.where((k) => k.tag == 'O').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (aKegs.isNotEmpty) ...[
          const Text(
            "TAG-A",
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          _gridPart(aKegs),
        ],
        const SizedBox(height: 8),
        if (oKegs.isNotEmpty) ...[
          const Text(
            "TAG-O",
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          _gridPart(oKegs),
        ],
      ],
    );
  }

  Widget _gridPart(List<Keg> list) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 10,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 1.6,
      ),
      itemCount: list.length,
      itemBuilder: (c, i) {
        var k = list[i];
        bool isS = selectedKegIds.contains(k.id);
        bool canS = _isSelectable(k);
        Color bg = isS
            ? Colors.black
            : (canS
                  ? (k.status == 'CLEANED'
                        ? Colors.green[50]!
                        : (k.status == 'FILLED'
                              ? Colors.grey[200]!
                              : Colors.white))
                  : Colors.grey[400]!);
        return GestureDetector(
          onTap: canS
              ? () => setState(() {
                  if (selectedJob == 'TAP') selectedKegIds.clear();
                  isS ? selectedKegIds.remove(k.id) : selectedKegIds.add(k.id);
                })
              : null,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              color: bg,
            ),
            child: Center(
              child: Text(
                k.id,
                style: TextStyle(
                  color: isS
                      ? Colors.white
                      : (canS ? Colors.black : Colors.black26),
                  fontSize: 7,
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
    // --- 判定ロジックを修正 ---
    List<String> ac3Alerts = [];
    if (selectedJob == 'CLEAN') {
      for (var id in selectedKegIds) {
        // allKegsからIDで検索
        int idx = allKegs.indexWhere((k) => k.id == id);
        if (idx != -1 && allKegs[idx].ac25Count >= ac3Threshold) {
          ac3Alerts.add(id);
        }
      }
    }
    String btnText =
        (selectedJob == 'TAP' && tapMaster[selectedTapSlot] != null)
        ? "TAP OUT"
        : "SET";
    Color btnColor =
        (selectedJob == 'TAP' && tapMaster[selectedTapSlot] != null)
        ? Colors.red[700]!
        : Colors.black;

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
                "⚠️ AC3推奨ケグあり: ${ac3Alerts.join(', ')}",
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                onPressed: _execute,
                child: Text(
                  btnText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
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
    // TANK_EDIT のコードは完全に削除しました！

    // CLEAN
    if (selectedJob == 'CLEAN') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoBox('KEG', '${selectedKegIds.length}', 'selected'),
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
      // ★ UPDATE: 画面下部の TANK 情報も Supabase から取得
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
          _infoBox('KEGS', '${selectedKegIds.length}', 'selected'),
        ],
      );
    }

    if (selectedJob == 'MOVE') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoBox('KEGS', '${selectedKegIds.length}', 'selected'),
          const Text(
            'TO',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          _infoBox('LOC', selectedLocation, 'Destination'),
        ],
      );
    }

    if (selectedJob == 'TAP') {
      String? currentId = tapMaster[selectedTapSlot];
      String kegDisp =
          currentId ?? (selectedKegIds.isEmpty ? '?' : selectedKegIds.first);
      String beerName = '-';
      String dateInfo = 'Target';
      if (currentId != null) {
        int idx = allKegs.indexWhere((k) => k.id == currentId);
        if (idx != -1) {
          var k = allKegs[idx];
          beerName = k.contents;
          var log = k.history.firstWhere(
            (l) => l.action == 'TAP IN',
            orElse: () =>
                KegLog(timestamp: DateTime.now(), action: '', detail: ''),
          );
          dateInfo = DateFormat('MM/dd HH:mm').format(log.timestamp);
        }
      } else if (selectedKegIds.isNotEmpty) {
        beerName = allKegs
            .firstWhere((k) => k.id == selectedKegIds.first)
            .contents;
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoBox('KEG', kegDisp, beerName),
          const Text(
            'TO',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          _infoBox('TAP', selectedTapSlot, dateInfo),
        ],
      );
    }

    return Row(
      children: [
        Text('${selectedKegIds.length} Kegs Selected'),
        if (selectedJob == 'MEMO')
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                controller: _memoController,
                decoration: const InputDecoration(hintText: 'Memo...'),
              ),
            ),
          ),
      ],
    );
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
    List<Keg> sortedKegs = List.from(allKegs);
    sortedKegs.sort((a, b) {
      bool aHasMemo = a.currentMemo.isNotEmpty;
      bool bHasMemo = b.currentMemo.isNotEmpty;
      if (aHasMemo != bHasMemo) return aHasMemo ? -1 : 1;
      if (a.tag != b.tag) return a.tag.compareTo(b.tag);
      return a.number.compareTo(b.number);
    });

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ListView.builder(
            itemCount: sortedKegs.length,
            itemBuilder: (c, i) {
              var k = sortedKegs[i];
              bool isSel = dataSelectedKegId == k.id;
              String lastTime = k.history.isEmpty
                  ? '-'
                  : DateFormat('MM/dd HH:mm').format(k.history.first.timestamp);
              bool hasMemo = k.currentMemo.isNotEmpty;
              return GestureDetector(
                onTap: () => setState(() => dataSelectedKegId = k.id),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: hasMemo ? Colors.amber[300]! : Colors.black,
                    ),
                    color: isSel ? Colors.black12 : Colors.white,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${k.id} ${k.status}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          Text(lastTime, style: const TextStyle(fontSize: 8)),
                        ],
                      ),
                      Text(
                        '${k.contents} / ${k.location}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 3,
          child: dataSelectedKegId == null
              ? const Center(child: Text('Select Keg'))
              : _buildDetail(
                  allKegs.firstWhere((k) => k.id == dataSelectedKegId),
                ),
        ),
      ],
    );
  }

  Widget _buildDetail(Keg k) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.black,
          width: double.infinity,
          child: Text(
            '${k.id} [${k.status}]',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (k.currentMemo.isNotEmpty)
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            color: Colors.amber[50],
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.push_pin, size: 16, color: Colors.orange),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'MEMO: ${k.currentMemo}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'AC25: ${k.ac25Count}回 / ${k.contents}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: k.history.length,
            itemBuilder: (c, i) {
              var log = k.history[i];
              bool isLatest = (i == 0);
              return ListTile(
                dense: true,
                leading: Text(
                  DateFormat('MM/dd HH:mm').format(log.timestamp),
                  style: const TextStyle(fontSize: 10),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      color: Colors.black,
                      child: Text(
                        log.action,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        log.detail + (log.memo != null ? ' (${log.memo})' : ''),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                trailing: isLatest
                    ? IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.red,
                        ),
                        onPressed: () => _undoLatestHistory(k),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSetTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'KEG REGISTRATION',
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
                decoration: const InputDecoration(labelText: 'Qty'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _addKegSizeController,
                decoration: const InputDecoration(labelText: 'Size L'),
                keyboardType: TextInputType.number,
              ),
            ),
            ElevatedButton(onPressed: _addKegsBatch, child: const Text("ADD")),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'DELETE KEG',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _tagBtn(deletionTag, 'A', (t) => setState(() => deletionTag = t)),
            _tagBtn(deletionTag, 'O', (t) => setState(() => deletionTag = t)),
            Expanded(
              child: TextField(
                controller: _delKegIdController,
                decoration: const InputDecoration(labelText: 'No.'),
                keyboardType: TextInputType.number,
              ),
            ),
            ElevatedButton(
              onPressed: _deleteKegByInput,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[100]),
              child: const Text("DELETE"),
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
                decoration: const InputDecoration(labelText: 'New Location'),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (_newLocController.text.isNotEmpty) {
                  setState(() => externalLocs.add(_newLocController.text));
                  _saveData();
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
                    _saveData();
                  },
                ),
              )
              .toList(),
        ),
        ListTile(
          title: const Text('AC3 Threshold'),
          subtitle: TextField(
            controller: _ac3Controller,
            keyboardType: TextInputType.number,
            onSubmitted: (v) => setState(() {
              ac3Threshold = int.parse(v);
              _saveData();
            }),
          ),
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

  void _addKegsBatch() {
    int count = int.tryParse(_addKegCountController.text) ?? 0;
    String size = "${_addKegSizeController.text}L";
    if (count <= 0) return;
    setState(() {
      var currentTagKegs = allKegs
          .where((k) => k.tag == registrationTag)
          .toList();
      int startNum = currentTagKegs.isEmpty
          ? 1
          : currentTagKegs
                    .map((k) => k.number)
                    .reduce((a, b) => a > b ? a : b) +
                1;
      for (int i = 0; i < count; i++) {
        allKegs.add(
          Keg(tag: registrationTag, number: startNum + i, size: size),
        );
      }
      _saveData();
      _addKegCountController.clear();
    });
  }

  void _deleteKegByInput() {
    int? num = int.tryParse(_delKegIdController.text);
    if (num == null) return;
    String targetId = "$deletionTag-$num";
    setState(() {
      allKegs.removeWhere((k) => k.id == targetId);
      _saveData();
      _delKegIdController.clear();
    });
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
          selectedKegIds.clear();
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
          selectedKegIds.clear();
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

// --- ここから INVENTORY（材料マスタ・在庫管理）タブ ---
// --- ここからファイルの最後まで上書き ---

// 1. 在庫管理タブ
class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});
  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('item_master')
          .select()
          .order('category_code');
      setState(() {
        _items = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showItemDialog([Map<String, dynamic>? existingItem]) {
    final isEdit = existingItem != null;
    final nameC = TextEditingController(
      text: isEdit ? existingItem['name'] : '',
    );
    String cat = isEdit ? existingItem['category_code'] : 'M';
    String unit = isEdit ? (existingItem['unit'] ?? 'kg') : 'kg';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(isEdit ? '材料編集' : '新規登録'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: '材料名'),
              ),
              DropdownButton<String>(
                value: cat,
                items: ['A', 'C', 'H', 'M', 'N', 'P', 'Y']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setD(() => cat = v!),
              ),
              DropdownButton<String>(
                value: unit,
                items: ['kg', 'g', 'L', 'ml', '個', 'pack']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setD(() => unit = v!),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final d = {
                  'name': nameC.text,
                  'category_code': cat,
                  'unit': unit,
                };
                if (isEdit)
                  await _supabase
                      .from('item_master')
                      .update(d)
                      .eq('id', existingItem['id']);
                else {
                  d['id'] = '$cat-${DateTime.now().millisecondsSinceEpoch}';
                  await _supabase.from('item_master').insert(d);
                }
                Navigator.pop(context);
                _fetchItems();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.black,
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'INVENTORY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton(
                onPressed: () => _showItemDialog(),
                child: const Text('新規登録'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text(item['category_code'])),
                      title: Text(item['name']),
                      subtitle: Text('単位: ${item['unit']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showItemDialog(item),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ItemLedgerScreen(item: item),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// 2. 在庫通帳（詳細）
class ItemLedgerScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  const ItemLedgerScreen({super.key, required this.item});
  @override
  State<ItemLedgerScreen> createState() => _ItemLedgerScreenState();
}

class _ItemLedgerScreenState extends State<ItemLedgerScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _txs = [];
  double _stock = 0.0;
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final data = await _supabase
        .from('inventory_transactions')
        .select()
        .eq('item_id', widget.item['id'])
        .order('created_at', ascending: false);
    double s = 0;
    for (var r in data) {
      double a = (r['amount'] as num).toDouble();
      r['transaction_type'] == 'IN' ? s += a : s -= a;
    }
    setState(() {
      _txs = List<Map<String, dynamic>>.from(data);
      _stock = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item['name']),
        backgroundColor: Colors.amber,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text('現在高', style: TextStyle(color: Colors.white70)),
                Text(
                  '${_stock.toStringAsFixed(1)} ${widget.item['unit']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _txs.length,
              itemBuilder: (context, index) {
                final t = _txs[index];
                final isOut = t['transaction_type'] == 'OUT';
                return ListTile(
                  title: Text(t['memo'] ?? '-'),
                  trailing: Text(
                    '${isOut ? "-" : "+"}${t['amount']}',
                    style: TextStyle(
                      color: isOut ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 3. レシピ管理タブ
class RecipeMasterTab extends StatefulWidget {
  const RecipeMasterTab({super.key});
  @override
  State<RecipeMasterTab> createState() => _RecipeMasterTabState();
}

class _RecipeMasterTabState extends State<RecipeMasterTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _recipes = [];
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final data = await _supabase
        .from('recipes')
        .select()
        .order('created_at', ascending: false);
    setState(() {
      _recipes = List<Map<String, dynamic>>.from(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.black,
          padding: const EdgeInsets.all(12),
          child: const Text(
            'RECIPE LIST',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _recipes.length,
            itemBuilder: (context, index) {
              final r = _recipes[index];
              return ListTile(
                title: Text(r['name'] ?? ''),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RecipeDetailScreen(recipe: r),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// 4. レシピ詳細（BOM）
class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  const RecipeDetailScreen({super.key, required this.recipe});
  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final data = await _supabase
        .from('recipe_items')
        .select('amount, item_master(name, unit)')
        .eq('recipe_id', widget.recipe['id']);
    setState(() {
      _items = List<Map<String, dynamic>>.from(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.recipe['name'])),
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final it = _items[index];
          return ListTile(
            title: Text(it['item_master']['name']),
            trailing: Text('${it['amount']} ${it['item_master']['unit']}'),
          );
        },
      ),
    );
  }
}

// 5. タンクデータタブ
class TankDataTab extends StatefulWidget {
  const TankDataTab({super.key});
  @override
  State<TankDataTab> createState() => _TankDataTabState();
}

class _TankDataTabState extends State<TankDataTab> {
  final _supabase = Supabase.instance.client;
  int _selectedTankId = 1;
  List<Map<String, dynamic>> _tanks = [];
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _recipes = [];
  bool _isLoading = true;

  final _tempController = TextEditingController();
  final _sgController = TextEditingController();
  final _phController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final tanksData = await _supabase.from('tanks').select().order('id');
      final recipesData = await _supabase
          .from('recipes')
          .select()
          .order('name');

      // 選択中のタンクのログを取得
      final currentTank = tanksData.firstWhere(
        (t) => t['id'] == _selectedTankId,
      );
      final batchId = currentTank['current_batch_id'];
      List<Map<String, dynamic>> logsData = [];
      if (batchId != null) {
        logsData = await _supabase
            .from('tank_logs')
            .select()
            .eq('batch_id', batchId)
            .order('created_at', ascending: false);
      }

      setState(() {
        _tanks = List<Map<String, dynamic>>.from(tanksData);
        _recipes = List<Map<String, dynamic>>.from(recipesData);
        _logs = List<Map<String, dynamic>>.from(logsData);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('取得エラー: $e');
      setState(() => _isLoading = false);
    }
  }

  // グラフ描画（簡易版）
  Widget _buildTrendGraph(String? startTime) {
    if (startTime == null || _logs.isEmpty)
      return const Center(child: Text('データなし'));
    // ここに fl_chart を使ったグラフ処理が入ります
    return Container(
      height: 150,
      width: double.infinity,
      color: Colors.white10,
      child: const Center(
        child: Text('発酵グラフ表示エリア', style: TextStyle(color: Colors.white54)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      );
    final currentTank = _tanks.firstWhere((t) => t['id'] == _selectedTankId);

    return Row(
      children: [
        // 左側：タンク選択リスト
        Container(
          width: 100,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Colors.white12)),
          ),
          child: ListView.builder(
            itemCount: _tanks.length,
            itemBuilder: (context, index) {
              final t = _tanks[index];
              final isSel = _selectedTankId == t['id'];
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTankId = t['id']);
                  _fetchData();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  color: isSel ? Colors.amber : Colors.transparent,
                  child: Center(
                    child: Text(
                      'TANK ${t['id']}',
                      style: TextStyle(
                        color: isSel ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // 右側：詳細表示
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentTank['current_recipe'] ?? 'Empty',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                // グラフ
                _buildTrendGraph(currentTank['start_time']),
                const SizedBox(height: 20),
                // 入力フォーム
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tempController,
                        decoration: const InputDecoration(labelText: 'Temp'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _sgController,
                        decoration: const InputDecoration(labelText: 'SG'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(onPressed: () {}, child: const Text('SAVE')),
                  ],
                ),
                const Divider(height: 40),
                const Text('RECENT LOGS'),
                ..._logs.map(
                  (l) => ListTile(
                    dense: true,
                    title: Text(l['action'] ?? 'MEASURE'),
                    subtitle: Text('T: ${l['temperature']} / S: ${l['sg']}'),
                    trailing: Text(l['created_at'].toString().substring(5, 10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 6. 履歴タブ
class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('History View (工事中)'));
  }
}
