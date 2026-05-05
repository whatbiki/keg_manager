import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'keg_model.dart';

class HistoryTab extends StatelessWidget {
  final List<Keg> allKegs;

  const HistoryTab({super.key, required this.allKegs});

  @override
  Widget build(BuildContext context) {
    // すべてのケグから履歴を抜き出して、一つのリストにまとめる
    List<Map<String, dynamic>> combinedLogs = [];
    for (var keg in allKegs) {
      for (var log in keg.history) {
        combinedLogs.add({
          'kegId': keg.id,
          'log': log,
        });
      }
    }

    // 日付が新しい順に並べ替え
    combinedLogs.sort((a, b) => b['log'].timestamp.compareTo(a['log'].timestamp));

    if (combinedLogs.isEmpty) {
      return const Center(child: Text('履歴はまだありません'));
    }

    return ListView.builder(
      itemCount: combinedLogs.length,
      itemBuilder: (context, index) {
        final item = combinedLogs[index];
        final KegLog log = item['log'];
        final String kegId = item['kegId'];

        return Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black12)),
          ),
          child: ListTile(
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(kegId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                const Icon(Icons.history, size: 16),
              ],
            ),
            title: Text(log.action, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${log.detail}\n${log.prevStatus} → ${log.prevContents}'),
            trailing: Text(
              DateFormat('MM/dd\nHH:mm').format(log.timestamp.toLocal()),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}