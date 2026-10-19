import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/storage/file_preferences.dart';

const firstId = '0123456789abcdef0123456789abcdef';
const nextId = 'abcdef0123456789abcdef0123456789';

class UrsBackend {
  final requests = <http.Request>[];
  int initialFlag = 0;
  int challengeLogins = 1;
  int verificationChallenges = 0;
  int loginCalls = 0;
  int ticketCalls = 0;
  int verificationCalls = 0;
  String? loginChallengeId;
  String loginChallengeRet = '447';
  bool includeInitialId = true;

  http.Client client() => MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    Map<String, dynamic> body;
    final headers = <String, String>{};
    if (path.endsWith('/ini')) {
      body = {
        'ret': 201,
        'capFlag': initialFlag,
        if (includeInitialId) 'capId': firstId,
      };
      headers['set-cookie'] = 'URS_SESSION=initial-session; Path=/';
    } else if (path.endsWith('/powGetP')) {
      body = {'ret': 201};
    } else if (path.endsWith('/gt')) {
      body = {'ret': 201, 'tk': 'ticket-${++ticketCalls}'};
    } else if (path.endsWith('/l')) {
      loginCalls++;
      if (loginCalls <= challengeLogins) {
        body = {
          'ret': loginChallengeRet,
          if (loginChallengeId != null) 'capId': loginChallengeId,
        };
      } else {
        body = {'ret': 201};
        headers['set-cookie'] =
            'S_INFO=test-session; Path=/, P_INFO=test-account; Path=/';
      }
    } else if (const ['/vfscp', '/vftcp', '/vfccp'].any(path.endsWith)) {
      verificationCalls++;
      expect(
        request.headers['cookie'],
        contains('URS_SESSION=initial-session'),
      );
      expect(request.headers['content-type'], 'application/json');
      final envelope = jsonDecode(request.body) as Map;
      expect(envelope.keys, ['encParams']);
      expect(envelope['encParams'], matches(r'^[a-f0-9]+$'));
      expect(request.body, isNot(contains('widget-proof')));
      body = verificationCalls <= verificationChallenges
          ? {'ret': 447, 'capId': nextId}
          : {'ret': 201};
      headers['set-cookie'] = 'URS_VERIFIED=yes; Path=/';
    } else if (path == '/users/login') {
      expect(request.headers['cookie'], contains('S_INFO=test-session'));
      body = {'status': 'ok'};
    } else if (path == '/users/oversea/login_check') {
      body = {
        'status': 'ok',
        'data': {'token': 'oversea-test-token'},
      };
    } else {
      throw StateError('Unexpected login request: $path');
    }
    return http.Response(jsonEncode(body), 200, headers: headers);
  });

  List<String> get paths => requests.map((r) => r.url.path).toList();
}

void main() {
  late Directory temp;
  late UrsBackend backend;
  final originalFactory = LoginService.clientFactory;
  final originalPreferences = CoreRuntime.preferences;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-captcha-test-');
    backend = UrsBackend();
    LoginService.clientFactory = backend.client;
    CoreRuntime.preferences = () => FilePreferences.open(temp.path);
  });

  tearDown(() async {
    LoginService.clientFactory = originalFactory;
    CoreRuntime.preferences = originalPreferences;
    await temp.delete(recursive: true);
  });

  Future<LoginSession> login({LoginCaptchaHandler? onCaptcha}) =>
      LoginService.loginWithEmail(
        email: 'account@qq.com',
        password: 'test-only-password',
        rememberPassword: false,
        onCaptcha: onCaptcha,
      );

  test(
    '447 keeps the original cookie jar and obtains a fresh login ticket',
    () async {
      final prompts = <LoginCaptchaChallenge>[];
      final session = await login(
        onCaptcha: (challenge) async {
          prompts.add(challenge);
          return 'widget-proof';
        },
      );

      expect(prompts.single.captchaId, firstId);
      expect(prompts.single.capFlag, 6);
      expect(backend.ticketCalls, 2);
      expect(backend.paths, [
        '/dl/zj/mail/ini',
        '/dl/zj/mail/powGetP',
        '/dl/zj/mail/gt',
        '/dl/zj/mail/l',
        '/dl/zj/mail/vfscp',
        '/dl/zj/mail/powGetP',
        '/dl/zj/mail/gt',
        '/dl/zj/mail/l',
        '/users/login',
      ]);
      final retry = backend.requests
          .where((r) => r.url.path.endsWith('/l'))
          .last;
      expect(retry.headers['cookie'], contains('URS_VERIFIED=yes'));
      expect(session.kind, LoginSessionKind.domestic);
      expect(session.savedPassword, isNull);
      final stored = await FilePreferences.open(temp.path);
      expect(stored.getString('login_password_v1'), isNull);
      expect((await LoginService.readLoginSession())?.email, 'account@qq.com');
    },
  );

  test('initial challenge is completed before sending a password', () async {
    backend.initialFlag = 6;
    backend.challengeLogins = 0;
    await login(
      onCaptcha: (_) async {
        expect(backend.loginCalls, 0);
        return 'widget-proof';
      },
    );
    expect(backend.paths[1], '/dl/zj/mail/vfscp');
    expect(backend.ticketCalls, 1);
  });

  test(
    'headless login reports a typed human challenge without changing channels',
    () async {
      await expectLater(
        login(),
        throwsA(
          isA<LoginCaptchaRequired>().having(
            (e) => e.challenge.capFlag,
            'capFlag',
            6,
          ),
        ),
      );
      expect(backend.loginCalls, 1);
      expect(backend.verificationCalls, 0);
      expect(backend.paths, isNot(contains('/users/oversea/login_check')));
      expect(await LoginService.readLoginSession(), isNull);
    },
  );

  test(
    'cancelling stops login and preserves an already saved session',
    () async {
      final stored = await FilePreferences.open(temp.path);
      await stored.apply({'login_email_v1': 'previous@example.test'});
      await expectLater(
        login(onCaptcha: (_) async => null),
        throwsA(
          isA<McDevException>().having(
            (e) => e.message,
            'message',
            contains('已取消'),
          ),
        ),
      );
      expect(backend.verificationCalls, 0);
      expect(backend.loginCalls, 1);
      expect(
        (await FilePreferences.open(temp.path)).getString('login_email_v1'),
        'previous@example.test',
      );
    },
  );

  test('a renewed challenge replaces the stale captcha identifier', () async {
    backend.verificationChallenges = 1;
    final ids = <String>[];
    await login(
      onCaptcha: (challenge) async {
        ids.add(challenge.captchaId);
        return 'widget-proof';
      },
    );
    expect(ids, [firstId, nextId]);
    expect(backend.verificationCalls, 2);
  });

  for (final entry in {'444': 'vftcp', '445': 'vfccp'}.entries) {
    test(
      '${entry.key} selects its matching URS verification endpoint',
      () async {
        backend.loginChallengeRet = entry.key;
        await login(onCaptcha: (_) async => 'widget-proof');
        expect(backend.paths, contains('/dl/zj/mail/${entry.value}'));
        expect(backend.paths, isNot(contains('/dl/zj/mail/vfscp')));
      },
    );
  }

  test('an endless challenge is bounded to three human prompts', () async {
    backend.challengeLogins = 10;
    var prompts = 0;
    await expectLater(
      login(
        onCaptcha: (_) async {
          prompts++;
          return 'widget-proof';
        },
      ),
      throwsA(
        isA<McDevException>().having(
          (e) => e.message,
          'message',
          contains('验证未通过'),
        ),
      ),
    );
    expect(prompts, 3);
    expect(backend.verificationCalls, 3);
    expect(await LoginService.readLoginSession(), isNull);
  });

  test(
    'missing captcha configuration fails without presenting an empty widget',
    () async {
      backend.includeInitialId = false;
      var prompted = false;
      await expectLater(
        login(
          onCaptcha: (_) async {
            prompted = true;
            return 'widget-proof';
          },
        ),
        throwsA(
          isA<McDevException>().having(
            (e) => e.message,
            'message',
            contains('验证码标识'),
          ),
        ),
      );
      expect(prompted, isFalse);
    },
  );

  test('ordinary domestic login does not present a captcha', () async {
    backend.challengeLogins = 0;
    await login(onCaptcha: (_) => throw StateError('Unexpected captcha'));
    expect(backend.loginCalls, 1);
    expect(backend.verificationCalls, 0);
  });

  test('oversea login retains its existing flow', () async {
    final session = await LoginService.loginWithEmail(
      email: 'account@gmail.com',
      password: 'test-only-password',
      rememberPassword: false,
      onCaptcha: (_) => throw StateError('Unexpected captcha'),
    );
    expect(session.kind, LoginSessionKind.oversea);
    expect(backend.paths, ['/users/oversea/login_check']);
  });
}
