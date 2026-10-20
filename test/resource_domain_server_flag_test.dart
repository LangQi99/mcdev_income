import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/core.dart';

void main() {
  test('sparse PE detail gets an explicit ordinary resource type marker', () {
    final draft = ResourceDraft(
      category: 'pe',
      source: {'item_name': 'Sparse addon', 'pri_type': 2, 'main_city': false},
    );

    final payload = draft.toPayload();

    expect(payload['is_domain_server_item'], 0);
    expect(payload['is_domain_server_item'], isA<int>());
    expect(payload['main_city'], isFalse);
  });

  test('domain-server and main-city selections remain independent', () {
    final hill = ResourceDraft(
      category: 'pe',
      source: {'is_domain_server_item': 1, 'main_city': false},
    ).toPayload();
    final city = ResourceDraft(
      category: 'pe',
      source: {'is_domain_server_item': 0, 'main_city': true},
    ).toPayload();

    expect(hill['is_domain_server_item'], 1);
    expect(hill['main_city'], isFalse);
    expect(city['is_domain_server_item'], 0);
    expect(city['main_city'], isTrue);
  });

  test(
    'boolean manifest values serialize as integer flags without mutation',
    () {
      for (final selected in [false, true]) {
        final draft = ResourceDraft(
          category: 'pe',
          source: {'is_domain_server_item': selected},
        );

        final payload = draft.toPayload();

        expect(payload['is_domain_server_item'], selected ? 1 : 0);
        expect(payload['is_domain_server_item'], isA<int>());
        expect(draft.get('is_domain_server_item'), selected);
      }
    },
  );

  test('null legacy markers use the ordinary resource default', () {
    final payload = ResourceDraft(
      category: 'pe',
      source: {'is_domain_server_item': null},
    ).toPayload();

    expect(payload['is_domain_server_item'], 0);
  });

  test('numeric text in imported drafts serializes as integer markers', () {
    for (final value in ['0', '1']) {
      final payload = ResourceDraft(
        category: 'pe',
        source: {'is_domain_server_item': value},
      ).toPayload();

      expect(payload['is_domain_server_item'], int.parse(value));
      expect(payload['is_domain_server_item'], isA<int>());
    }
  });

  test('unsupported markers are rejected before an upload', () {
    final draft = ResourceDraft(
      category: 'pe',
      source: {'is_domain_server_item': 2},
    );

    expect(draft.validate(ResourceOptions({})), contains('“我的山头”标记必须为 0 或 1'));
  });

  test('PC forms do not gain the PE domain-server marker', () {
    final payload = ResourceDraft(category: 'comp').toPayload();

    expect(payload.containsKey('is_domain_server_item'), isFalse);
  });
}
