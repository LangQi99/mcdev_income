import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/cli/resource_upload.dart';

import 'cli_test.dart' as cli_fixtures;
import 'resource_workflow_test.dart' as fixtures;

ResourceOptions lobbyOptions() {
  final data =
      jsonDecode(jsonEncode(fixtures.testOptions)) as Map<String, dynamic>;
  (data['pri_type']['pe'] as List).add({'id': 6, 'title': '联机大厅'});
  data['sub_type']['pe']['6'] = [
    {
      'id': 999,
      'title': '默认',
      'fp_type': 'zip_package',
      'file_type': 'zip',
      'lobby': true,
      'mod_version': true,
    },
  ];
  data['mod_version'] = ['3.4', '3.8', '3.9'];
  return ResourceOptions(data);
}

void main() {
  test('detail null DLC fields are converted before an HTTP save', () async {
    final source = fixtures.testResource()
      ..['dlc_info'] = {
        'dlc_switch': false,
        'dlc_type': 'off',
        'master': null,
        'slave_list': null,
      };
    Map<String, dynamic>? sent;
    final api = McDevApi(
      cookie: '',
      category: 'pe',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        final dlc = sent!['dlc_info'] as Map;
        // Match the official editor's object/list contract, independently of
        // the serializer. A detail response is not a valid save payload.
        if (dlc['master'] is! Map || dlc['slave_list'] is! List) {
          return http.Response('{"status":"error","msg":"params error"}', 200);
        }
        return fixtures.ok({'item_id': '123'});
      }),
    );
    addTearDown(api.close);
    await api.saveResource(
      resourceCategory: 'pe',
      itemId: '123',
      payload: ResourceDraft(category: 'pe', source: source).toPayload(),
    );
    expect(sent!['dlc_info'], {
      'dlc_switch': false,
      'dlc_type': 'off',
      'master': <String, dynamic>{},
      'slave_list': <dynamic>[],
    });
    expect(source['dlc_info']['master'], isNull);
    expect(source['dlc_info']['slave_list'], isNull);
  });

  test('empty PE optional values follow the official editor', () {
    final source = fixtures.testResource()
      ..addAll({'subject_id': '', 'game_host': null});
    final payload = ResourceDraft(category: 'pe', source: source).toPayload();
    expect(payload['subject_id'], isNull);
    expect(payload['game_host'], isNull);
    expect(source['subject_id'], '');
    expect(source['game_host'], isNull);
  });

  test('platform-generated lobby state is not echoed into an update', () {
    final source = fixtures.testResource()
      ..addAll({
        'lobby_res': {
          'mcp_signs': ['generated-signature'],
        },
        'lobby_config_op_log': [],
        'lobby_sort_key': {
          'self_test': ['score'],
        },
        'level_data': null,
        'level_data_version': null,
        'first_accept_time': '2025-08-07T07:31:19',
        'premium_apply_status': 'no_apply',
        'performance_service_status': 0,
        'future_setting': {'preserve': true},
      });
    final payload = ResourceDraft(category: 'pe', source: source).toPayload();
    for (final field in [
      'lobby_res',
      'lobby_config_op_log',
      'lobby_sort_key',
      'level_data',
      'level_data_version',
      'first_accept_time',
      'premium_apply_status',
      'performance_service_status',
    ]) {
      expect(payload.containsKey(field), false, reason: field);
    }
    expect(payload['future_setting'], {'preserve': true});
    expect(payload['res'], source['res']);
    expect(payload['channel'], source['channel']);
  });

  test(
    'enabled slave DLC normalizes a null list before adding its own entry',
    () {
      final source = fixtures.testResource()
        ..['dlc_info'] = {
          'dlc_switch': true,
          'dlc_type': 'slave',
          'master': {'item_id': '1', 'item_name': '主包'},
          'slave_list': null,
        };
      final payload = ResourceDraft(category: 'pe', source: source).toPayload();
      expect(payload['dlc_info']['slave_list'], [
        {'item_id': '123', 'item_name': '测试模组'},
      ]);
      expect(source['dlc_info']['slave_list'], isNull);
    },
  );

  test('commercial lobby omits subtype only in the outgoing form', () {
    final source = fixtures.testResource()
      ..addAll({
        'pri_type': 6,
        'sub_type': 999,
        'lobby_commercialize': true,
        'mod_version': '3.8',
      });
    final draft = ResourceDraft(category: 'pe', source: source);
    final payload = draft.toPayload(options: lobbyOptions());
    expect(payload.containsKey('sub_type'), false);
    expect(payload['mod_version'], '3.8');
    expect(draft.get('sub_type'), 999);
    draft.set('lobby_commercialize', false);
    expect(draft.toPayload(options: lobbyOptions())['sub_type'], 999);
    draft.set('pri_type', 2);
    draft.set('sub_type', 6);
    draft.set('lobby_commercialize', true);
    expect(draft.toPayload(options: lobbyOptions())['sub_type'], 6);
  });

  test('required SDK version errors name the invalid field before upload', () {
    final draft = ResourceDraft(
      category: 'pe',
      source: fixtures.testResource()
        ..addAll({'pri_type': 6, 'sub_type': 999, 'mod_version': '0.0'}),
    );
    expect(
      draft.validate(lobbyOptions()),
      contains('请选择有效的 ModSDK 版本（mod_version）'),
    );
    draft.set('mod_version', '3.8');
    expect(draft.validate(lobbyOptions()), isEmpty);
  });

  test(
    'package replacement uses the normalized form at the save boundary',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mcdev-form-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final package = await File(
        '${directory.path}/B7.zip',
      ).writeAsBytes([80, 75, 3, 4]);
      final backend = cli_fixtures.Backend();
      backend.resource.addAll({
        'pri_type': 6,
        'sub_type': 999,
        'mod_version': '3.4',
        'lobby_commercialize': true,
        'pri_effect_type': null,
        'sub_effect_type': null,
        'dlc_info': {
          'dlc_switch': false,
          'dlc_type': 'off',
          'master': null,
          'slave_list': null,
        },
      });
      backend.onSave = () async {
        final payload = backend.payload!;
        expect(payload.containsKey('pri_effect_type'), false);
        expect(payload.containsKey('sub_effect_type'), false);
        expect(payload.containsKey('sub_type'), false);
        expect(payload['dlc_info']['master'], isA<Map>());
        expect(payload['dlc_info']['slave_list'], isA<List>());
        expect(payload['mod_version'], '3.8');
      };
      final api = backend.api();
      addTearDown(api.close);
      final result =
          await ResourceUpload(
            api: api,
            home: directory.path,
            owner: 'test',
            category: 'pe',
            options: lobbyOptions(),
            prices: ResourcePriceSettings({}),
          ).execute({
            'fields': {'mod_version': '3.8'},
            'packages': [
              {'path': package.path, 'replace': 0},
            ],
          }, itemId: '123');
      expect(result['item_id'], '123');
      expect(backend.saves, 1);
      expect(backend.uploaded, hasLength(1));
      expect(backend.resource['mod_version'], '3.4');
      expect(backend.resource['dlc_info']['master'], isNull);
    },
  );
}
