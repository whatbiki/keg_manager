import 'package:flutter/material.dart';

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

  // ★ factory メソッド (fromJson) が抜けていたので追加します！
  factory Keg.fromJson(Map<String, dynamic> json) {
    var k = Keg(
      tag: json['tg'],
      number: json['n'],
      status: json['s'],
      ac25Count: json['c'],
      contents: json['con'],
      date: json['d'],
      location: json['l'],
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
