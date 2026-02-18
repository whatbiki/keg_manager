import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() => runApp(const AgarthaApp());

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
    );
    k.history = (json['h'] as List).map((e) => KegLog.fromJson(e)).toList();
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
  late List<Keg> allKegs = [];
  late List<Tank> allTanks = [];
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
    for (int i = 1; i <= 8; i++) tapMaster['TAP 0$i'] = null;
    _loadData();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'agartha_final_v23',
      jsonEncode(allKegs.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      'agartha_tank_v23',
      jsonEncode(allTanks.map((e) => e.toJson()).toList()),
    );
    await prefs.setString('agartha_ext_v23', jsonEncode(externalLocs));
    await prefs.setInt('agartha_ac3_v23', ac3Threshold);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ac3Threshold = prefs.getInt('agartha_ac3_v23') ?? 4;
      _ac3Controller.text = ac3Threshold.toString();
      String? kj = prefs.getString('agartha_final_v23');
      String? tj = prefs.getString('agartha_tank_v23');
      String? ej = prefs.getString('agartha_ext_v23');

      allKegs = kj != null
          ? (jsonDecode(kj) as List).map((e) => Keg.fromJson(e)).toList()
          : [];
      allTanks = tj != null
          ? (jsonDecode(tj) as List).map((e) => Tank.fromJson(e)).toList()
          : List.generate(
              4,
              (i) => Tank(id: i + 1, beerName: 'セゾン', brewDate: '2026/03/15'),
            );
      if (ej != null) externalLocs = List<String>.from(jsonDecode(ej));

      _syncTapMaster();
      _updateControllers();
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
    _beerNameController.text = allTanks[selectedTankId - 1].beerName;
    _dateController.text = allTanks[selectedTankId - 1].brewDate;
  }

  void _execute() {
    setState(() {
      if (selectedJob == 'TANK_EDIT') {
        allTanks[selectedTankId - 1].beerName = _beerNameController.text;
        allTanks[selectedTankId - 1].brewDate = _dateController.text;
        selectedJob = 'FILL IN';
      } else if (selectedJob == 'MEMO') {
        for (var id in selectedKegIds) {
          int idx = allKegs.indexWhere((k) => k.id == id);
          if (idx != -1) {
            allKegs[idx].addLog(
              'MEMO',
              'User Memo',
              memo: _memoController.text,
            );
            allKegs[idx].currentMemo = _memoController.text;
          }
        }
        _memoController.clear();
      } else if (selectedJob == 'TAP') {
        _handleTapProcess();
      } else {
        for (var id in selectedKegIds) {
          int idx = allKegs.indexWhere((k) => k.id == id);
          if (idx == -1) continue;
          var k = allKegs[idx];
          if (selectedJob == 'CLEAN') {
            k.addLog('CLEAN', selectedCleanOption);
            k.status = 'CLEANED';
            if (selectedCleanOption.contains('AC3'))
              k.ac25Count = 0;
            else
              k.ac25Count++;
            k.contents = '-';
            k.date = '-';
          } else if (selectedJob == 'FILL IN') {
            var t = allTanks[selectedTankId - 1];
            k.addLog('FILL IN', 'Tank ${t.id} -> ${t.beerName}');
            k.status = 'FILLED';
            k.contents = t.beerName;
            k.date = t.brewDate;
            k.location = '冷蔵庫';
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
            }
          }
        }
      }
      selectedKegIds.clear();
      _saveData();
    });
  }

  void _handleTapProcess() {
    String? currentKegIdInTap = tapMaster[selectedTapSlot];
    if (currentKegIdInTap == null) {
      if (selectedKegIds.length == 1) {
        String newId = selectedKegIds.first;
        int idx = allKegs.indexWhere((k) => k.id == newId);
        allKegs[idx].addLog('TAP IN', 'Opened at $selectedTapSlot');
        allKegs[idx].location = selectedTapSlot;
        allKegs[idx].status = 'TAPPED';
        tapMaster[selectedTapSlot] = newId;
      }
    } else {
      int idx = allKegs.indexWhere((k) => k.id == currentKegIdInTap);
      if (idx != -1) {
        allKegs[idx].addLog('TAP OUT', 'Empty at $selectedTapSlot');
        allKegs[idx].status = 'EMPTY';
        allKegs[idx].location = '倉庫';
        allKegs[idx].contents = '-';
      }
      tapMaster[selectedTapSlot] = null;
    }
  }

  void _undoLatestHistory(Keg k) {
    if (k.history.isEmpty) return;
    setState(() {
      KegLog latest = k.history.removeAt(0);
      k.status = latest.prevStatus;
      k.contents = latest.prevContents;
      k.location = latest.prevLocation;
      if (latest.action == 'CLEAN') {
        if (latest.detail.contains('AC3'))
          k.ac25Count = ac3Threshold;
        else if (k.ac25Count > 0)
          k.ac25Count--;
      }
      _syncTapMaster();
      _saveData();
    });
  }

  bool _isSelectable(Keg k) {
    if (selectedJob == 'CLEAN') return k.status == 'EMPTY';
    if (selectedJob == 'FILL IN') return k.status == 'CLEANED';
    if (selectedJob == 'MOVE') return (k.status == 'FILLED');
    if (selectedJob == 'TAP')
      return k.status == 'FILLED' &&
          k.location == '冷蔵庫' &&
          tapMaster[selectedTapSlot] == null;
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
            'KEG MANAGER',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          Row(children: ['JOB', 'DATA', 'SET'].map((t) => _tabNav(t)).toList()),
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
    if (selectedTab == 'DATA') return _buildDataTab();
    if (selectedTab == 'SET') return _buildSetTab();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildJobTab(),
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
        if (selectedJob == 'FILL IN' || selectedJob == 'TANK_EDIT') ...[
          Row(
            children: [
              const SizedBox(width: 50, child: Text('TANK')),
              for (int i = 1; i <= 4; i++)
                _sqBtn(i.toString(), selectedTankId == i, () {
                  setState(() {
                    selectedTankId = i;
                    _updateControllers();
                    if (selectedJob == 'TANK_EDIT')
                      selectedJob = 'TANK_EDIT';
                    else
                      selectedJob = 'FILL IN';
                  });
                }),
              _sqBtn(
                'EDIT',
                selectedJob == 'TANK_EDIT',
                () => setState(() => selectedJob = 'TANK_EDIT'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 50, top: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Text(
                '${allTanks[selectedTankId - 1].beerName}  ${allTanks[selectedTankId - 1].brewDate}',
                style: const TextStyle(fontSize: 18),
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
    if (allKegs.isEmpty)
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No Kegs Registered."),
        ),
      );
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
    if (selectedJob == 'TANK_EDIT') {
      return Column(
        children: [
          Text(
            'EDITING TANK $selectedTankId',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: _beerNameController,
            decoration: const InputDecoration(labelText: 'Beer Name'),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Date: ${_dateController.text}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  DateTime? p = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (p != null)
                    setState(
                      () => _dateController.text = DateFormat(
                        'yyyy/MM/dd',
                      ).format(p),
                    );
                },
              ),
            ],
          ),
        ],
      );
    }
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
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoBox(
            'TANK',
            '$selectedTankId',
            allTanks[selectedTankId - 1].beerName,
          ),
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
      String kegDisp = currentId == null
          ? (selectedKegIds.isEmpty ? '?' : selectedKegIds.first)
          : currentId;
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
    String size = _addKegSizeController.text + "L";
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
