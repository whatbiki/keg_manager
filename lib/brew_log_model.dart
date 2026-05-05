class BrewLog {
  String batchNo; // 仕込No.
  String recipeName; // 品名（セゾンアガルタ等）
  DateTime brewDate; // 仕込日時

  // 原材料（マスタから引っ張る）
  Map<String, double> malts; // 例: {'ピルスナー': 26.6}
  Map<String, double> hops; // 例: {'SSG': 638.3}
  Map<String, double> others; // 副材料・薬品

  // 工程数値
  double og; // 初期比重
  double fg; // 最終比重
  double abv; // アルコール分
  double strikeWater; // 仕込水
  double spargeWater; // スパージング

  // 詰口実績（ケグデータから集計）
  int count19L;
  int count10L;
  double totalVolume; // 合計詰口数量

  BrewLog({
    required this.batchNo,
    required this.recipeName,
    required this.brewDate,
    this.malts = const {},
    this.hops = const {},
    this.others = const {},
    this.og = 0.0,
    this.fg = 0.0,
    this.abv = 0.0,
    this.strikeWater = 0.0,
    this.spargeWater = 0.0,
    this.count19L = 0,
    this.count10L = 0,
    this.totalVolume = 0.0,
  });

  // CSV一行分（スプレッドシート用）に出力するメソッド
  String toCsvRow() {
    return [
      batchNo,
      recipeName,
      brewDate.toIso8601String(),
      og.toString(),
      fg.toString(),
      abv.toString(),
      totalVolume.toString(),
      // ... 必要な項目を並べる
    ].join(',');
  }
}
