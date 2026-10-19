import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/services/login_captcha.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const challenge = LoginCaptchaChallenge(
    captchaId: '0123456789abcdef0123456789abcdef',
    capFlag: 6,
  );
  const nonce = '0123456789abcdef0123456789abcdef';

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NeteaseLoginCaptcha.channel, null);
  });

  test(
    'native bridge carries captcha configuration and receives a proof',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NeteaseLoginCaptcha.channel, (call) async {
            expect(call.method, 'verify');
            final args = call.arguments as Map;
            expect(args.keys.toSet(), {'html', 'nonce'});
            expect(args['nonce'], matches(r'^[a-f0-9]{32}$'));
            expect(args['html'], contains(challenge.captchaId));
            expect(args['html'], isNot(contains('account@qq.com')));
            expect(args['html'], isNot(contains('password')));
            return 'widget-proof';
          });
      expect(await NeteaseLoginCaptcha.verify(challenge), 'widget-proof');
    },
  );

  test('closing the native sheet returns cancellation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NeteaseLoginCaptcha.channel,
          (_) async => null,
        );
    expect(await NeteaseLoginCaptcha.verify(challenge), isNull);
  });

  test('empty native proofs are rejected before contacting URS', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NeteaseLoginCaptcha.channel,
          (_) async => ' ',
        );
    await expectLater(
      NeteaseLoginCaptcha.verify(challenge),
      throwsFormatException,
    );
  });

  test('invalid configuration cannot inject code into the captcha page', () {
    expect(
      () => NeteaseLoginCaptcha.buildPage(
        const LoginCaptchaChallenge(
          captchaId: '</script><script>bad()</script>',
          capFlag: 6,
        ),
        nonce: nonce,
      ),
      throwsFormatException,
    );
    expect(
      () => NeteaseLoginCaptcha.buildPage(challenge, nonce: '<script>'),
      throwsFormatException,
    );
  });

  test(
    'captcha page uses the official URS endpoints and a bounded result bridge',
    () {
      final html = NeteaseLoginCaptcha.buildPage(challenge, nonce: nonce);
      expect(html, contains('https://cstaticdun.126.net/load.min.js'));
      expect(html, contains('webzjcaptcha.reg.163.com'));
      expect(html, contains('webzjac.reg.163.com'));
      expect(html, contains('data.validate.length<=16384'));
      expect(html, contains('nonce:config.nonce'));
      expect(html, isNot(contains('mcdev.webapp.163.com')));
      expect(html, isNot(contains('__MCDEV_CONFIG__')));
    },
  );
}
