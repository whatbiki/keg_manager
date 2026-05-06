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
  // フォーム用の変数
  // ==========================================
  String _txType = 'IN';
  final _qtyController = TextEditingController(); // 数量 (amount)
  final _priceController = TextEditingController(); // 価格 (price)
  final _memoController = TextEditingController(); // メモ (memo)
  int? _selectedSupplierId;
  List<Map<String, dynamic>> _suppliersList = [];

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

  // 仕入先リストの取得
  Future<void> _fetchSuppliersMain() async {
    final data = await _supabase.from('suppliers').select().order('id');
    if (mounted) {
      setState(() {
        _suppliersList = List<Map<String, dynamic>>.from(data);
      });
    }
  }

  // アイテムリストの取得
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

  // ==========================================
  // 通帳に記録（入出庫の保存）
  // ==========================================
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
      });

      if (!mounted) return;

      // 保存成功したら入力欄を空にする
      _qtyController.clear();
      _priceController.clear();
      _memoController.clear();
      setState(() {
        _selectedSupplierId = null;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('通帳に記録しました！')));

      // TODO: ここで履歴リストと総在庫量を再取得する処理を後で追加
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ==========================================
  // 新規アイテム登録ダイアログ
  // ==========================================
  void _showAddDialog() {
    final nameC = TextEditingController();
    String selCat = 'M';

    // ★ 追加1: 単位の初期値と、選択肢のリストを作ります
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
            mainAxisSize: MainAxisSize.min, // 中身に合わせて高さを縮める
            children: [
              // カテゴリ選択
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

              // 材料名入力
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: '材料名'),
              ),
              const SizedBox(height: 8),

              // ★ 追加2: 単位を選ぶドロップダウンを追加
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
                if (nameC.text.trim().isEmpty) return; // 空白なら保存しない

                await _supabase.from('item_master').insert({
                  'id': '$selCat-${DateTime.now().millisecondsSinceEpoch}',
                  'name': nameC.text.trim(),
                  'category_code': selCat,
                  // ★ 追加3: 決め打ちではなく、選んだ単位（selUnit）を保存する
                  'unit': selUnit,
                });

                if (!mounted) return;
                Navigator.pop(context);
                _fetch(); // リストを再取得
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
                          _selectedItem = null; // カテゴリを変えたら選択解除
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
                                _txType = 'IN'; // 選んだ時はデフォルトで入庫に
                              });
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
                                    '在庫: 0.0 ${_selectedItem!['unit']}',
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
                                  // IN / OUT ラジオボタン
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
                                  const SizedBox(height: 8),

                                  // 入力欄
                                  Row(
                                    children: [
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
                                      if (_txType == 'IN')
                                        const SizedBox(width: 8),

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
                                                  overflow: TextOverflow
                                                      .ellipsis, // ★念のため文字が長すぎる時は「...」で省略する設定も追加
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (v) => setState(
                                              () => _selectedSupplierId = v,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 16),

                                      SizedBox(
                                        height: 56,
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
                                ],
                              ),
                            ),
                            const Divider(height: 1),

                            // 履歴リスト領域
                            Expanded(
                              child: Container(
                                color: Colors.grey[50],
                                child: const Center(
                                  child: Text('ここに時系列の取引履歴（リスト）が並びます'),
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
