import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/korean_arb.dart';

String visible(String text) => text.replaceAll(wordJoiner, '|');

void main() {
  test('joins the characters of each Korean word', () {
    expect(visible(keepAll('복구 문구')), '복|구 문|구');
  });

  test('keeps Latin words and numbers attached to Korean together', () {
    expect(visible(keepAll('Ledger를 연결')), 'Ledger|를 연|결');
    expect(visible(keepAll('3개')), '3|개');
    expect(visible(keepAll('ZEC 보내기')), 'ZEC 보|내|기');
  });

  test('attaches particles to placeholders', () {
    expect(visible(keepAll('{name}님')), '{name}|님');
    expect(visible(keepAll('총{count}')), '총|{count}');
  });

  test('leaves English, punctuation and spaces alone', () {
    expect(keepAll('Enter your passphrase.'), 'Enter your passphrase.');
    expect(visible(keepAll('완료. 다음')), '완|료. 다|음');
  });

  test('is idempotent', () {
    const text = '지갑을 가져오려면 {count}개 단어를 입력하세요';
    expect(keepAll(keepAll(text)), keepAll(text));
  });

  test('builds the ARB without touching metadata or ICU syntax', () {
    final built =
        jsonDecode(
              buildKoreanArb(
                jsonEncode({
                  '@@locale': 'ko',
                  'count': '{count, plural, other{계정 {count}개}}',
                  '@count': {'description': '설명'},
                }),
              ),
            )
            as Map;
    expect(built['@@locale'], 'ko');
    expect(built['@count'], {'description': '설명'});
    expect(
      visible(built['count'] as String),
      '{count, plural, other{계|정 {count}|개}}',
    );
  });
}
