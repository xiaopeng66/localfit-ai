import 'dart:io';

/// BERT/BGE WordPiece 分词（Dart 实现，docs/39 §4.2）。
///
/// 与 HuggingFace `BertTokenizerFast`（tokenizer.json：BertNormalizer +
/// BertPreTokenizer + WordPiece）对齐的**纯 Dart** 实现——端上嵌入的输入
/// 必须与模型训练时分词一致，否则向量空间整个漂移（docs/39 §13 的
/// 「分词接错，向量全错但看起来能跑」）。golden 分词测试钉住中文、英文、
/// 数字、标点与 emoji 的行为。
///
/// 三步：
/// 1. **BertNormalizer**：去控制符/零宽、去 combining 音标、CJK 字符两侧
///    补空格（`handle_chinese_chars`）、空白归一；
/// 2. **BertPreTokenizer**：按空白与标点切开；
/// 3. **WordPiece**：贪心最长匹配，非首段加 `##`，整词无匹配给 `[UNK]`。
final class BertWordPieceTokenizer {
  BertWordPieceTokenizer._({
    required this.vocab,
    required this.unkToken,
    required this.maxInputCharsPerWord,
  });

  final Map<String, int> vocab;
  final String unkToken;
  final int maxInputCharsPerWord;

  /// 特殊符号的固定 id（BERT 词表的 0/100/101/102）。
  static const int padTokenId = 0;
  static const int unkTokenId = 100;
  static const int clsTokenId = 101;
  static const int sepTokenId = 102;

  /// 从词表文件加载（每行一个 token，行号即 id；BERT 官方 21128 行）。
  static Future<BertWordPieceTokenizer> loadVocabFile(String path) async {
    final lines = await File(path).readAsLines();
    return fromVocabLines(lines);
  }

  static BertWordPieceTokenizer fromVocabLines(List<String> lines) {
    final vocab = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final token = lines[i].replaceAll('\r', '');
      vocab[token] = i;
    }
    return BertWordPieceTokenizer._(
      vocab: vocab,
      unkToken: '[UNK]',
      maxInputCharsPerWord: 100,
    );
  }

  int get vocabSize => vocab.length;

  int tokenToId(String token) => vocab[token] ?? vocab['[UNK]']!;

  /// BertNormalizer（`clean_text` + `handle_chinese_chars` + 去音标；
  /// 本模型 `lowercase: false`，不改大小写）。
  String normalize(String text) {
    final out = StringBuffer();
    for (final ch in text.runes) {
      final cp = ch;
      // 去控制符 / 替换符 / 代理对。
      if (cp == 0 || cp == 0xFFFD || (0xD800 <= cp && cp <= 0xDFFF)) continue;
      final character = String.fromCharCode(cp);
      // 去 combining（Mn 类）——本模型 strip_accents: null = 按 clean 处理。
      if (_isCombiningMark(cp)) continue;
      // CJK 两侧补空格（中文按「字」切开是 BERT 中文模型的训练口径）。
      if (_isCjk(cp)) {
        out
          ..write(' ')
          ..write(character)
          ..write(' ');
        continue;
      }
      // 空白归一成单空格。
      if (cp == 0x20 || (cp >= 0x09 && cp <= 0x0D) || _isUnicodeSpace(cp)) {
        out.write(' ');
        continue;
      }
      out.write(character);
    }
    return out.toString();
  }

  /// BertPreTokenizer：空白切分 + 标点独立成段。
  List<String> preTokenize(String text) {
    final normalized = normalize(text);
    final result = <String>[];
    for (final chunk in normalized.split(RegExp(r'\s+'))) {
      if (chunk.isEmpty) continue;
      result.addAll(_splitPunctuation(chunk));
    }
    return result;
  }

  List<String> _splitPunctuation(String chunk) {
    final parts = <String>[];
    final current = StringBuffer();
    for (final ch in chunk.runes) {
      if (_isPunct(ch)) {
        if (current.isNotEmpty) {
          parts.add(current.toString());
          current.clear();
        }
        parts.add(String.fromCharCode(ch));
      } else {
        current.writeCharCode(ch);
      }
    }
    if (current.isNotEmpty) parts.add(current.toString());
    return parts;
  }

  /// WordPiece 贪心最长匹配。整词失败 ⇒ `[UNK]`（与 HF 口径一致）。
  List<String> wordPiece(String token) {
    if (token.runes.length > maxInputCharsPerWord) return [unkToken];
    final chars = token.split('');
    final pieces = <String>[];
    var start = 0;
    while (start < chars.length) {
      var end = chars.length;
      String? matched;
      while (start < end) {
        var sub = chars.sublist(start, end).join();
        if (start > 0) sub = '##$sub';
        if (vocab.containsKey(sub)) {
          matched = sub;
          break;
        }
        end--;
      }
      if (matched == null) return [unkToken];
      pieces.add(matched);
      start += matched.startsWith('##') ? matched.length - 2 : matched.length;
    }
    return pieces;
  }

  /// 全管线：文本 → WordPiece token 序列（不含 [CLS]/[SEP]）。
  List<String> tokenize(String text) {
    final tokens = <String>[];
    for (final piece in preTokenize(text)) {
      tokens.addAll(wordPiece(piece));
    }
    return tokens;
  }

  /// 编码到模型输入：[CLS] tokens [SEP]，超过 [maxLen] 截断
  /// （[CLS]/[SEP] 占 2 个位置）。
  List<int> encode(String text, {int maxLen = 64}) {
    final ids = <int>[clsTokenId];
    for (final token in tokenize(text)) {
      if (ids.length >= maxLen - 1) break;
      ids.add(tokenToId(token));
    }
    ids.add(sepTokenId);
    return ids;
  }

  /// attention mask（1 = 真实 token，0 = padding）。
  List<int> attentionMask(List<int> inputIds) => [
    for (final id in inputIds) id == padTokenId ? 0 : 1,
  ];

  /// BGE 检索前缀（docs/39 §4.2 前缀策略 A）。
  static const String bgeQueryPrefix = '为这个句子生成表示以用于检索相关文章：';

  /// 批量编码为模型输入张量（inputIds / attentionMask / tokenTypeIds）。
  ///
  /// 返回扁平 List（与 `OrtValue.fromList(data, shape)` 配套）。
  ({
    List<int> inputIds,
    List<int> attentionMask,
    List<int> tokenTypeIds,
    List<int> shape,
  })
  encodeBatch(List<String> texts, {int maxLen = 64}) {
    final inputIds = <int>[];
    final attention = <int>[];
    final tokenTypes = <int>[];
    for (final text in texts) {
      final ids = encode(text, maxLen: maxLen);
      final mask = attentionMask(ids);
      inputIds.addAll(ids);
      attention.addAll(mask);
      tokenTypes.addAll(List.filled(ids.length, 0));
      final pad = maxLen - ids.length;
      inputIds.addAll(List.filled(pad, padTokenId));
      attention.addAll(List.filled(pad, 0));
      tokenTypes.addAll(List.filled(pad, 0));
    }
    return (
      inputIds: inputIds,
      attentionMask: attention,
      tokenTypeIds: tokenTypes,
      shape: [texts.length, maxLen],
    );
  }
}

bool _isCjk(int cp) {
  // BERT 原版 `handle_chinese_chars` 的区段（含扩展）。
  return (cp >= 0x4E00 && cp <= 0x9FFF) ||
      (cp >= 0x3400 && cp <= 0x4DBF) ||
      (cp >= 0x20000 && cp <= 0x2A6DF) ||
      (cp >= 0x2A700 && cp <= 0x2B73F) ||
      (cp >= 0x2B740 && cp <= 0x2B81F) ||
      (cp >= 0x2B920 && cp <= 0x2CEAF) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0x2F800 && cp <= 0x2FA1F);
}

bool _isPunct(int cp) {
  // ASCII 标点 + Unicode P 类（BERT 原版口径）。
  const ascii = r'''!-/:-@\[-`{-~''';
  if (cp >= 0x21 && cp <= 0x2F) return true;
  if (cp >= 0x3A && cp <= 0x40) return true;
  if (cp >= 0x5B && cp <= 0x60) return true;
  if (cp >= 0x7B && cp <= 0x7E) return true;
  if (ascii.contains(String.fromCharCode(cp))) return true;
  final category = _unicodeCategory(cp);
  return category == 'P' || category == 'S';
}

bool _isCombiningMark(int cp) => _unicodeCategory(cp) == 'Mn';

bool _isUnicodeSpace(int cp) {
  const spaces = [0xA0, 0x1680, 0x202F, 0x205F, 0x3000];
  if (spaces.contains(cp)) return true;
  return cp >= 0x2000 && cp <= 0x200A;
}

/// 极简 Unicode 类别表：只覆盖本分词器用到的两类（Mn 音标、P/S 标点），
/// 区段取自 BERT 原版 Python 实现（`_is_punctuation` / `_is_control`）的
/// 等价范围，不引入完整 UC 表。
String _unicodeCategory(int cp) {
  // 常见 combining 区段（Mn）。
  if ((cp >= 0x0300 && cp <= 0x036F) ||
      (cp >= 0x1AB0 && cp <= 0x1AFF) ||
      (cp >= 0x1DC0 && cp <= 0x1DFF) ||
      (cp >= 0x20D0 && cp <= 0x20FF) ||
      (cp >= 0xFE20 && cp <= 0xFE2F)) {
    return 'Mn';
  }
  // 常见标点/符号区段（中英混排实际会遇到的）。注意全角拉丁/数字
  // （0xFF01–0xFF5E）里 0xFF01–0xFF20 与 0xFF3B–0xFF40 等才是标点，
  // 字母区段（0xFF21–0xFF3A / 0xFF41–0xFF5A）与数字（0xFF10–0xFF19）
  // 必须仍算「字母」，否则 ＢＣＤ 会被切成三段 [UNK]（HF 是整段一个）。
  if ((cp >= 0x2000 && cp <= 0x206F) || // 通用标点
      (cp >= 0x3000 && cp <= 0x303F) || // CJK 标点
      (cp >= 0x2018 && cp <= 0x201F)) {
    return 'P';
  }
  if (cp == 0xFF01 ||
      (cp >= 0xFF08 && cp <= 0xFF09) ||
      cp == 0xFF0C ||
      (cp >= 0xFF1A && cp <= 0xFF1B) ||
      cp == 0xFF1F ||
      (cp >= 0xFF3B && cp <= 0xFF3D) ||
      cp == 0xFF5B ||
      cp == 0xFF5D) {
    return 'P';
  }
  if ((cp >= 0xFF10 && cp <= 0xFF19) ||
      (cp >= 0xFF21 && cp <= 0xFF3A) ||
      (cp >= 0xFF41 && cp <= 0xFF5A)) {
    return 'L';
  }
  return 'L';
}
