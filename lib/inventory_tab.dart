import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});
  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  String _selectedCategory = 'M';
  Map<String, dynamic>? _selectedItem;

  // ==========================================
  // フォーム・計算用の変数
  // ==========================================
  String _txType = 'IN';
  DateTime _selectedDate = DateTime.now(); // ★ 追加: 選択された日付
  final _qtyController = TextEditingController();
  final _priceController = TextEditingController();
  final _memoController = TextEditingController();
  int? _selectedSupplierId;
  List<Map<String, dynamic>> _suppliersList = [];

  List<Map<String, dynamic>> _transactions = [];
  double _currentStock = 0.0;
  bool _loadingTx = false;

  final Map<String, String> categories = {
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
    _fetch();
    _fetchSuppliersMain();
  }

  Future<void> _fetchSuppliersMain() async {
    final data = await _supabase.from('suppliers').select().order('id');
    if (mounted) {
      setState(() {
        _suppliersList = List<Map<String, dynamic>>.from(data);
      });
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final data = await _supabase
        .from('item_master')
        .select()
        .eq('category_code', _selectedCategory)
        .order('name');
    if (mounted) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  // ★ 追加: カレンダーで日付を選ぶメソッド
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020), // 過去はこの年から
      lastDate: DateTime(2100), // 未来はこの年まで
    );
    if (picked != null) {
      setState(() {
        // 並び順がおかしくならないよう、時間は「入力した時の現在時刻」を維持します
        final now = DateTime.now();
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          now.hour,
          now.minute,
          now.second,
        );
      });
    }
  }

  Future<void> _fetchTransactions(String itemId) async {
    setState(() => _loadingTx = true);
    try {
      final data = await _supabase
          .from('inventory_transactions')
          .select()
          .eq('item_id', itemId)
          .order('created_at', ascending: false);

      double stock = 0.0;
      for (var tx in data) {
        final amount = (tx['amount'] as num).toDouble();
        if (tx['transaction_type'] == 'IN') {
          stock += amount;
        } else {
          stock -= amount;
        }
      }

      if (!mounted) return;
      setState(() {
        _transactions = List<Map<String, dynamic>>.from(data);
        _currentStock = stock;
        _loadingTx = false;
      });
    } catch (e) {
      debugPrint('履歴取得エラー: $e');
      if (mounted) setState(() => _loadingTx = false);
    }
  }

  Future<void> _saveTransaction() async {
    if (_qtyController.text.isEmpty) return;

    final amount = double.tryParse(_qtyController.text);
    final price = double.tryParse(_priceController.text) ?? 0.0;

    if (amount == null || amount <= 0) return;

    try {
      await _supabase.from('inventory_transactions').insert({
        'item_id': _selectedItem!['id'],
        'transaction_type': _txType,
        'amount': amount,
        'unit': _selectedItem!['unit'],
        'price': price,
        'memo': _memoController.text,
        'supplier_id': _txType == 'IN' ? _selectedSupplierId : null,
        'created_at': _selectedDate.toIso8601String(), // ★ 追加: 指定した日付を保存！
      });

      if (!mounted) return;

      _qtyController.clear();
      _priceController.clear();
      _memoController.clear();
      setState(() {
        _selectedSupplierId = null;
        _selectedDate = DateTime.now(); // 保存したら「今日」にリセットする
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('通帳に記録しました！')));

      _fetchTransactions(_selectedItem!['id']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddDialog() {
    final nameC = TextEditingController();
    String selCat = 'M';
    String selUnit = 'kg';
    final List<String> unitOptions = ['kg', 'g', 'L', 'ml', '個', 'pack'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text(
            '材料登録',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selCat,
                items: categories.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.key}: ${e.value}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setD(() => selCat = v!),
                decoration: const InputDecoration(labelText: 'カテゴリ'),
              ),
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: '材料名'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selUnit,
                items: unitOptions
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) => setD(() => selUnit = v!),
                decoration: const InputDecoration(labelText: '単位'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                if (nameC.text.trim().isEmpty) return;

                await _supabase.from('item_master').insert({
                  'id': '$selCat-${DateTime.now().millisecondsSinceEpoch}',
                  'name': nameC.text.trim(),
                  'category_code': selCat,
                  'unit': selUnit,
                });
                if (!mounted) return;
                Navigator.pop(context);
                _fetch();
              },
              child: const Text('SAVE', style: TextStyle(color: Colors.white)),
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
        // ==========================================
        // 上部ヘッダー
        // ==========================================
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ITEM MASTER',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (dialogContext) =>
                            const SupplierManagerDialog(),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                    ),
                    child: const Text(
                      'SUPPLIERS',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _showAddDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                    ),
                    child: const Text(
                      'NEW ITEM',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ==========================================
        // メイン画面（3ペイン）
        // ==========================================
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. 左側：カテゴリ ---
              Container(
                width: 60,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.grey[300]!)),
                ),
                child: ListView(
                  children: categories.keys.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat;
                          _selectedItem = null;
                        });
                        _fetch();
                      },
                      child: Container(
                        height: 60,
                        color: isSelected ? Colors.amber : Colors.transparent,
                        child: Center(
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // --- 2. 中央：アイテムリスト ---
              Expanded(
                flex: 2,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.black),
                      )
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black),
                              ),
                              child: Center(child: Text(item['category_code'])),
                            ),
                            title: Text(
                              item['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              categories[item['category_code']] ?? '',
                            ),
                            tileColor: _selectedItem?['id'] == item['id']
                                ? Colors.blue[50]
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedItem = item;
                                _txType = 'IN';
                              });
                              _fetchTransactions(item['id']);
                            },
                          );
                        },
                      ),
              ),

              Container(width: 1, color: Colors.grey[300]),

              // --- 3. 右側：通帳画面 ---
              Expanded(
                flex: 3,
                child: Container(
                  color: Colors.white,
                  child: _selectedItem == null
                      ? const Center(
                          child: Text(
                            '中央のアイテムをタップすると通帳が出ます',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 通帳ヘッダー
                            Container(
                              padding: const EdgeInsets.all(24),
                              color: Colors.blueGrey[50],
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _selectedItem!['name'],
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '在庫: ${_currentStock.toStringAsFixed(1)} ${_selectedItem!['unit']}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 入力フォーム
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              color: Colors.white,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Radio<String>(
                                        value: 'IN',
                                        groupValue: _txType,
                                        onChanged: (v) =>
                                            setState(() => _txType = v!),
                                        activeColor: Colors.blue,
                                      ),
                                      const Text(
                                        '入庫 (IN)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Radio<String>(
                                        value: 'OUT',
                                        groupValue: _txType,
                                        onChanged: (v) =>
                                            setState(() => _txType = v!),
                                        activeColor: Colors.red,
                                      ),
                                      const Text(
                                        '出庫 (OUT)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // ★★★ 入力欄を2段に分けました！ ★★★
                                  // --- 1段目：日付、数量、総額 ---
                                  Row(
                                    children: [
                                      // 日付選択（タップするとカレンダーが出ます）
                                      Expanded(
                                        child: InkWell(
                                          onTap: _pickDate,
                                          child: InputDecorator(
                                            decoration: const InputDecoration(
                                              labelText: '日付',
                                              border: OutlineInputBorder(),
                                            ),
                                            child: Text(
                                              '${_selectedDate.year}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // 数量
                                      Expanded(
                                        child: TextField(
                                          controller: _qtyController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText:
                                                '数量 (${_selectedItem!['unit']})',
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // 総額 (INのみ)
                                      if (_txType == 'IN')
                                        Expanded(
                                          child: TextField(
                                            controller: _priceController,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: '総額 (円)',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                      if (_txType ==
                                          'OUT') // OUTの時はレイアウトが崩れないよう空箱を置く
                                        const Expanded(child: SizedBox()),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // --- 2段目：メモ、仕入先、SAVEボタン ---
                                  Row(
                                    children: [
                                      // メモ
                                      Expanded(
                                        child: TextField(
                                          controller: _memoController,
                                          decoration: const InputDecoration(
                                            labelText: 'メモ (ロット等)',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // 仕入先 (INのみ)
                                      if (_txType == 'IN')
                                        Expanded(
                                          child: DropdownButtonFormField<int>(
                                            isExpanded: true,
                                            value: _selectedSupplierId,
                                            decoration: const InputDecoration(
                                              labelText: '仕入先',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: _suppliersList.map((s) {
                                              return DropdownMenuItem<int>(
                                                value: s['id'] as int,
                                                child: Text(
                                                  s['name'],
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (v) => setState(
                                              () => _selectedSupplierId = v,
                                            ),
                                          ),
                                        ),
                                      if (_txType == 'OUT')
                                        const Expanded(child: SizedBox()),
                                      const SizedBox(width: 16),

                                      // SAVEボタン
                                      SizedBox(
                                        height: 56,
                                        width: 120, // ボタンの幅を固定
                                        child: ElevatedButton(
                                          onPressed: _saveTransaction,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.black,
                                          ),
                                          child: const Text(
                                            'SAVE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // ★★★ ここまで ★★★
                                ],
                              ),
                            ),
                            const Divider(height: 1),

                            // 履歴リスト領域
                            Expanded(
                              child: Container(
                                color: Colors.grey[50],
                                child: _loadingTx
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : _transactions.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'まだ取引履歴がありません',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _transactions.length,
                                        itemBuilder: (context, index) {
                                          final tx = _transactions[index];
                                          final isIN =
                                              tx['transaction_type'] == 'IN';
                                          final date = DateTime.parse(
                                            tx['created_at'],
                                          ).toLocal();
                                          final dateStr =
                                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                                          return Card(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 4,
                                            ),
                                            child: ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor: isIN
                                                    ? Colors.blue[100]
                                                    : Colors.red[100],
                                                child: Text(
                                                  isIN ? 'IN' : 'OUT',
                                                  style: TextStyle(
                                                    color: isIN
                                                        ? Colors.blue[800]
                                                        : Colors.red[800],
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              title: Text(
                                                '${isIN ? "+" : "-"}${tx['amount']} ${tx['unit']}',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: isIN
                                                      ? Colors.blue[700]
                                                      : Colors.red[700],
                                                ),
                                              ),
                                              subtitle: Text(
                                                '$dateStr${tx['memo'] != null && tx['memo'] != '' ? ' | メモ: ${tx['memo']}' : ''}',
                                              ),
                                              trailing:
                                                  tx['price'] != null &&
                                                      tx['price'] > 0
                                                  ? Text(
                                                      '¥${tx['price']}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 仕入先管理専用のダイアログWidget
// ==========================================
class SupplierManagerDialog extends StatefulWidget {
  const SupplierManagerDialog({super.key});

  @override
  State<SupplierManagerDialog> createState() => _SupplierManagerDialogState();
}

class _SupplierManagerDialogState extends State<SupplierManagerDialog> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _suppliers = [];
  bool _loading = true;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
  }

  Future<void> _fetchSuppliers() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase.from('suppliers').select().order('id');
      if (!mounted) return;
      setState(() {
        _suppliers = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      debugPrint('仕入先取得エラー: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _addSupplier() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    try {
      await _supabase.from('suppliers').insert({'name': name});
      _nameController.clear();
      _fetchSuppliers();
    } catch (e) {
      debugPrint('仕入先追加エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '仕入先 (SUPPLIERS)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: '新しい仕入先を入力',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle,
                    color: Colors.black,
                    size: 32,
                  ),
                  onPressed: _addSupplier,
                ),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : _suppliers.isEmpty
                  ? const Center(child: Text('まだ登録されていません'))
                  : ListView.builder(
                      itemCount: _suppliers.length,
                      itemBuilder: (context, index) {
                        final sup = _suppliers[index];
                        return ListTile(
                          leading: const Icon(Icons.business),
                          title: Text(sup['name']),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}
