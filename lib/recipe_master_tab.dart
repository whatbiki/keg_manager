import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecipeMasterTab extends StatefulWidget {
  const RecipeMasterTab({super.key});

  @override
  State<RecipeMasterTab> createState() => _RecipeMasterTabState();
}

class _RecipeMasterTabState extends State<RecipeMasterTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _recipes = [];
  bool _loading = true;

  // --- 材料(BOM)用の変数 ---
  List<Map<String, dynamic>> _allMasterItems = []; // 材料の選択肢（プルダウン用）
  List<Map<String, dynamic>> _recipeItems = []; // 選んだレシピに紐づく材料リスト
  bool _loadingItems = false;

  // 選択中のレシピ情報
  Map<String, dynamic>? _selectedRecipe;

  // 編集用のコントローラー
  final _nameController = TextEditingController();
  final _ogController = TextEditingController();
  final _fgController = TextEditingController();
  final _abvController = TextEditingController();
  final _ibuController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchRecipes();
    _fetchAllMasterItems(); // 画面を開いた時にすべての材料リストを読み込んでおく
  }

  // --- 全材料を読み込む（プルダウン用） ---
  Future<void> _fetchAllMasterItems() async {
    final data = await _supabase
        .from('item_master')
        .select()
        .order('category_code')
        .order('name');
    if (mounted) {
      setState(() => _allMasterItems = List<Map<String, dynamic>>.from(data));
    }
  }

  // --- レシピ一覧を取得 ---
  Future<void> _fetchRecipes() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase.from('recipes').select().order('id');
      if (!mounted) return;
      setState(() {
        _recipes = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      debugPrint('レシピ取得エラー: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- レシピの材料(BOM)を取得 ---
  Future<void> _fetchRecipeItems(int recipeId) async {
    setState(() => _loadingItems = true);
    try {
      // データベースからは一旦そのまま取得する（.order('id') は外します）
      final data = await _supabase
          .from('recipe_items')
          .select()
          .eq('recipe_id', recipeId);

      List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(data);

      // ==========================================
      // ★ 追加: カテゴリ順（A, C, H, M...）に並び替える！
      // ==========================================
      items.sort((a, b) {
        // それぞれのアイテムのマスターデータ（カテゴリと名前）を探す
        final masterA = _allMasterItems.firstWhere(
          (m) => m['id'] == a['item_id'],
          orElse: () => {'category_code': 'Z', 'name': ''},
        );
        final masterB = _allMasterItems.firstWhere(
          (m) => m['id'] == b['item_id'],
          orElse: () => {'category_code': 'Z', 'name': ''},
        );

        // 1. カテゴリコードでアルファベット順に比較
        int catCompare = masterA['category_code'].toString().compareTo(
          masterB['category_code'].toString(),
        );

        if (catCompare != 0) {
          return catCompare; // カテゴリが違う場合はカテゴリ順
        }
        // 2. カテゴリが同じ場合は、名前順に並べる（例：Pilsnerより先にMunichが来るなど）
        return masterA['name'].toString().compareTo(masterB['name'].toString());
      });

      if (!mounted) return;
      setState(() {
        _recipeItems = items;
        _loadingItems = false;
      });
    } catch (e) {
      debugPrint('材料取得エラー: $e');
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  // --- リストからレシピを選んだ時の処理 ---
  void _selectRecipe(Map<String, dynamic> recipe) {
    setState(() {
      _selectedRecipe = recipe;
      _nameController.text = recipe['name'] ?? '';
      _ogController.text = recipe['target_og']?.toString() ?? '';
      _fgController.text = recipe['target_fg']?.toString() ?? '';
      _abvController.text = recipe['target_abv']?.toString() ?? '';
      _ibuController.text = recipe['target_ibu']?.toString() ?? '';
    });
    // 選んだレシピの材料を引っ張ってくる
    _fetchRecipeItems(recipe['id']);
  }

  // --- 新規作成モードにする ---
  void _createNewRecipe() {
    setState(() {
      _selectedRecipe = null;
      _recipeItems = []; // 材料もリセット
      _nameController.clear();
      _ogController.clear();
      _fgController.clear();
      _abvController.clear();
      _ibuController.clear();
    });
  }

  // --- 保存（新規作成 or 上書き更新） ---
  Future<void> _saveRecipe() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('レシピ名は必須です！')));
      return;
    }

    final recipeData = {
      'name': _nameController.text.trim(),
      'target_og': double.tryParse(_ogController.text),
      'target_fg': double.tryParse(_fgController.text),
      'target_abv': double.tryParse(_abvController.text),
      'target_ibu': double.tryParse(_ibuController.text),
    };

    try {
      if (_selectedRecipe == null) {
        // 新規登録
        final response = await _supabase
            .from('recipes')
            .insert(recipeData)
            .select()
            .single();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('新規レシピを作成しました！')));
        // 新規作成したら、それを「選択状態」にして材料を追加できるようにする
        _selectRecipe(response);
      } else {
        // 上書き更新
        await _supabase
            .from('recipes')
            .update(recipeData)
            .eq('id', _selectedRecipe!['id']);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('レシピを更新しました！')));
      }
      _fetchRecipes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // --- 材料を追加するポップアップ ---
  void _showAddRecipeItemDialog() {
    if (_selectedRecipe == null) return; // レシピが保存されていなければ追加できない

    String? selectedItemId;
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text(
            '材料を追加',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 材料選択ドロップダウン
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: selectedItemId,
                decoration: const InputDecoration(
                  labelText: '材料を選択',
                  border: OutlineInputBorder(),
                ),
                items: _allMasterItems.map((item) {
                  return DropdownMenuItem<String>(
                    value: item['id'].toString(),
                    child: Text(
                      '[${item['category_code']}] ${item['name']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) => setD(() => selectedItemId = v),
              ),
              const SizedBox(height: 16),
              // 数量入力
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '使用量 (kg, L など)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                if (selectedItemId == null || amountController.text.isEmpty)
                  return;
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) return;

                try {
                  await _supabase.from('recipe_items').insert({
                    'recipe_id': _selectedRecipe!['id'],
                    'item_id': selectedItemId,
                    'amount': amount,
                  });
                  if (!mounted) return;
                  Navigator.pop(context); // ダイアログを閉じる
                  _fetchRecipeItems(_selectedRecipe!['id']); // リストを更新
                } catch (e) {
                  debugPrint('材料追加エラー: $e');
                }
              },
              child: const Text('ADD', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // --- 材料を削除する処理 ---
  Future<void> _deleteRecipeItem(int id) async {
    try {
      await _supabase.from('recipe_items').delete().eq('id', id);
      _fetchRecipeItems(_selectedRecipe!['id']); // リストを更新
    } catch (e) {
      debugPrint('材料削除エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ==========================================
        // 左側：レシピリスト
        // ==========================================
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: _createNewRecipe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text(
                      '+ NEW RECIPE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _recipes.length,
                          itemBuilder: (context, index) {
                            final recipe = _recipes[index];
                            final isSelected =
                                _selectedRecipe?['id'] == recipe['id'];
                            return ListTile(
                              title: Text(
                                recipe['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              subtitle: Text(
                                'ABV: ${recipe['target_abv'] ?? '-'}% | IBU: ${recipe['target_ibu'] ?? '-'}',
                              ),
                              tileColor: isSelected ? Colors.amber[100] : null,
                              onTap: () => _selectRecipe(recipe),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        // ==========================================
        // 右側：レシピ詳細＆編集フォーム
        // ==========================================
        Expanded(
          flex: 3,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedRecipe == null
                      ? '✨ 新規レシピ作成'
                      : '📝 レシピ編集 (ID: ${_selectedRecipe!['id']})',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'レシピ名 (例: Hazy IPA)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _ogController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Target OG',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _fgController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Target FG',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _abvController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Target ABV %',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _ibuController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Target IBU',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      height: 56,
                      width: 150,
                      child: ElevatedButton(
                        onPressed: _saveRecipe,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[800],
                        ),
                        child: const Text(
                          'SAVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // ==========================================
                // 3. 材料リスト（部品表: BOM）
                // ==========================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🌾 材料リスト (BOM)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_selectedRecipe != null)
                      ElevatedButton.icon(
                        onPressed: _showAddRecipeItemDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[700],
                        ),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text(
                          '材料を追加',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: Container(
                    color: Colors.grey[50],
                    child: _selectedRecipe == null
                        ? const Center(
                            child: Text(
                              'まずは上の基本情報を SAVE してレシピを作成してください',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : _loadingItems
                        ? const Center(child: CircularProgressIndicator())
                        : _recipeItems.isEmpty
                        ? const Center(
                            child: Text(
                              'まだ材料が登録されていません。右上のボタンから追加してください。',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _recipeItems.length,
                            itemBuilder: (context, index) {
                              final itemData = _recipeItems[index];
                              // item_id から マスターデータの名前と単位を探してくる
                              final masterItem = _allMasterItems.firstWhere(
                                (m) => m['id'] == itemData['item_id'],
                                orElse: () => {
                                  'name': '不明な材料',
                                  'unit': '',
                                  'category_code': '?',
                                },
                              );

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.black87,
                                    child: Text(
                                      masterItem['category_code'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    masterItem['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '使用量: ${itemData['amount']} ${masterItem['unit']}',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      // 削除する前に確認ダイアログを出すと親切です
                                      _deleteRecipeItem(itemData['id']);
                                    },
                                  ),
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
    );
  }
}
