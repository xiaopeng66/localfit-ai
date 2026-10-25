// 上屏预览导出（docs/29 §P8b-1 第 1 条）。
//
// 审核台要显示「这条在卡上长这样」，而卡片上的名称/品牌/环/三格全部是**派生**
// 出来的字符串。这些派生规则只许有一份实现：本脚本用 `dart run` 离线调用 App
// 自己的 [splitFoodName] / [normalizeFoodName] / [foodDisplayStrings]，把结果写成
// `reports/display_preview.jsonl` 给审核台读。
//
// **禁止在这里（或用 JS、或用 Python）重写一遍拆分规则**：两份实现必然漂移，
// 而漂移之后人审的就是一张并不存在的卡片，整个审核的意义就没了。规则变更时
// 重新跑本脚本即可，`--check` 会逐字节比对、陈旧就报错。
//
// 用法：
//   dart run tool/food_seed/review/export_display_preview.dart
//   dart run tool/food_seed/review/export_display_preview.dart --check
import 'dart:convert';
import 'dart:io';

import 'package:localfit_ai/utils/food_display.dart';
import 'package:localfit_ai/utils/food_name.dart';
import 'package:localfit_ai/utils/text_utils.dart';

const _seedPath = 'assets/seed/foods.v4.json';
const _outPath = 'reports/display_preview.jsonl';

/// 由 App 的同一批函数产出全部预览行（**唯一**的派生路径）。
List<String> renderPreviewLines(Map<String, Object?> seed, String sha256) {
  final foods = (seed['foods']! as List).cast<Map<String, Object?>>();
  double? number(Map<String, Object?> row, String key) =>
      (row[key] as num?)?.toDouble();
  final lines = <String>[
    jsonEncode(<String, Object?>{
      '_meta': <String, Object?>{
        'seed': _seedPath,
        'seed_sha256': sha256,
        'count': foods.length,
        'generator': 'tool/food_seed/review/export_display_preview.dart',
        // 审核台显示什么，完全由这三个函数决定（同源声明，测试据此对账）。
        'source_functions': <String>[
          'splitFoodName',
          'normalizeFoodName',
          'foodDisplayStrings',
        ],
      },
    }),
  ];
  for (final row in foods) {
    final raw = row['name']! as String;
    final split = splitFoodName(raw);
    final strings = foodDisplayStrings(
      name: normalizeFoodName(split.name),
      // 种子没有品牌列：品牌只可能来自拆分结果（有品牌的目录/自建条目才会
      // 走 `FoodCard.brand`，那类条目不在随包种子里）。
      brand: split.brand,
      kcalPer100g: number(row, 'kcal'),
      proteinPer100g: number(row, 'protein'),
      carbsPer100g: number(row, 'carbs'),
      fatPer100g: number(row, 'fat'),
    );
    lines.add(
      jsonEncode(<String, Object?>{
        'id': row['id'],
        'raw': raw,
        'name': strings.name,
        'brand': strings.brand,
        'ring': strings.kcalText,
        'ring_label': strings.kcalLabel,
        'protein': strings.proteinText,
        'carbs': strings.carbsText,
        'fat': strings.fatText,
      }),
    );
  }
  return lines;
}

String _sha256Of(List<int> bytes) {
  // 只用标准库：`crypto` 不是本项目依赖，这里也不需要密码学强度，但必须与
  // Python 侧（hashlib.sha256）**逐字节一致**——所以自己写 SHA-256。
  return _Sha256(bytes).hex();
}

void main(List<String> args) {
  final check = args.contains('--check');
  final seedFile = File(_seedPath);
  if (!seedFile.existsSync()) {
    stderr.writeln('种子不存在：$_seedPath');
    exit(2);
  }
  final seedBytes = seedFile.readAsBytesSync();
  final seed = jsonDecode(utf8.decode(seedBytes)) as Map<String, Object?>;
  final rendered =
      '${renderPreviewLines(seed, _sha256Of(seedBytes)).join('\n')}\n';
  final out = File(_outPath);

  if (check) {
    final current = out.existsSync() ? out.readAsStringSync() : '';
    if (current != rendered) {
      stderr.writeln('STALE: $_outPath 与当前种子/显示函数不一致，请重跑导出。');
      exit(1);
    }
    stdout.writeln(
      'OK: $_outPath 与种子（sha256 ${_sha256Of(seedBytes).substring(0, 12)}）一致',
    );
    return;
  }

  out.parent.createSync(recursive: true);
  out.writeAsStringSync(rendered);
  stdout.writeln('wrote $_outPath — ${rendered.split('\n').length - 2} 行预览');
}

/// 最小 SHA-256（FIPS 180-4）。写在这里而不是拉依赖：本仓 `dependencies` 里没有
/// 摘要库，P8b-1 明确要求「零新依赖」，而这个摘要是为了跟 Python 侧对账。
class _Sha256 {
  _Sha256(List<int> message)
    : _h = List<int>.from(_initial),
      _buffer = <int>[],
      _length = 0 {
    add(message);
    _finish();
  }

  static const List<int> _initial = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];

  static const List<int> _k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  final List<int> _h;
  final List<int> _buffer;
  int _length;

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  void add(List<int> bytes) {
    _length += bytes.length;
    _buffer.addAll(bytes);
    var offset = 0;
    while (_buffer.length - offset >= 64) {
      _compress(_buffer.sublist(offset, offset + 64));
      offset += 64;
    }
    if (offset > 0) _buffer.removeRange(0, offset);
  }

  void _compress(List<int> block) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      w[i] =
          (block[i * 4] << 24) |
          (block[i * 4 + 1] << 16) |
          (block[i * 4 + 2] << 8) |
          block[i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    _h[0] = (_h[0] + a) & 0xffffffff;
    _h[1] = (_h[1] + b) & 0xffffffff;
    _h[2] = (_h[2] + c) & 0xffffffff;
    _h[3] = (_h[3] + d) & 0xffffffff;
    _h[4] = (_h[4] + e) & 0xffffffff;
    _h[5] = (_h[5] + f) & 0xffffffff;
    _h[6] = (_h[6] + g) & 0xffffffff;
    _h[7] = (_h[7] + h) & 0xffffffff;
  }

  void _finish() {
    final bitLength = _length * 8;
    _buffer.add(0x80);
    while (_buffer.length % 64 != 56) {
      _buffer.add(0);
    }
    for (var i = 7; i >= 0; i--) {
      _buffer.add((bitLength >> (i * 8)) & 0xff);
    }
    for (var offset = 0; offset < _buffer.length; offset += 64) {
      _compress(_buffer.sublist(offset, offset + 64));
    }
  }

  String hex() => _h.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
}
