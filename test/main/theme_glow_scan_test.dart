// ============================================================================
// 阴影不得由强调色染色（彩色发光 = AI 感的主要来源之一）
// ============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/ 内不得有由 primary/secondary/tertiary 染色的 BoxShadow', () {
    // BoxShadow( 之后到该块结束前出现强调色引用，即视为发光阴影
    final accentRef = RegExp(r'\.(primary|secondary|tertiary)(Container)?\b');
    final offenders = <String>[];

    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('BoxShadow(')) continue;
        final block = lines.skip(i).take(8).join('\n');
        if (accentRef.hasMatch(block)) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(offenders, isEmpty, reason: '这些阴影用强调色染色，会让控件看起来在自发光');
  });
}
