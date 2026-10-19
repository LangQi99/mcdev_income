import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/core.dart';

void main() {
  for (final category in ['pe', 'comp']) {
    test(
      '$category omits null effect classifications without changing source',
      () {
        final draft = ResourceDraft(
          category: category,
          source: {
            'item_name': 'Ordinary resource',
            'pri_effect_type': null,
            'sub_effect_type': null,
            'game_host': null,
            'future_editable_field': {'enabled': true},
          },
        );

        final payload = draft.toPayload();

        expect(payload.containsKey('pri_effect_type'), isFalse);
        expect(payload.containsKey('sub_effect_type'), isFalse);
        expect(payload, containsPair('game_host', null));
        expect(payload['future_editable_field'], {'enabled': true});
        expect(draft.values, containsPair('pri_effect_type', null));
        expect(draft.values, containsPair('sub_effect_type', null));
      },
    );
  }

  test('selected effect classifications survive serialization', () {
    final draft = ResourceDraft(
      category: 'pe',
      source: {'pri_effect_type': 1, 'sub_effect_type': 0},
    );

    final payload = draft.toPayload();

    expect(payload['pri_effect_type'], 1);
    expect(payload['sub_effect_type'], 0);
  });

  test('missing optional classifications are not added to new resources', () {
    final payload = ResourceDraft(category: 'pe').toPayload();

    expect(payload.containsKey('pri_effect_type'), isFalse);
    expect(payload.containsKey('sub_effect_type'), isFalse);
  });
}
