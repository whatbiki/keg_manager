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

  // カテゴリ定義
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
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final data = await _supabase
        .from('item_master')
        .select()
        .order('category_code');
    setState(() {
      _items = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  void _showAddDialog() {
    final nameC = TextEditingController();
    String selCat = 'M';
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
                initialValue: selCat,
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
                await _supabase.from('item_master').insert({
                  'id': '$selCat-${DateTime.now().millisecondsSinceEpoch}',
                  'name': nameC.text,
                  'category_code': selCat,
                  'unit': selCat == 'M' || selCat == 'H' ? 'kg' : 'L',
                });
                //Navigator.pop(context);
                if (!mounted) return;
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
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ITEM MASTER',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: _showAddDialog,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                child: const Text(
                  'NEW ITEM',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
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
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(categories[item['category_code']] ?? ''),
              );
            },
          ),
        ),
      ],
    );
  }
}
