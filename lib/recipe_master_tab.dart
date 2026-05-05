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

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final data = await _supabase.from('recipes').select().order('name');
    setState(() {
      _recipes = List<Map<String, dynamic>>.from(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // JOBタブと同じトーンの見出し
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RECIPE LIST',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                child: const Text(
                  'ADD RECIPE',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _recipes.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(
                _recipes[i]['name'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ),
      ],
    );
  }
}
