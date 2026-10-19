import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core.dart';

/// Only the public captcha configuration and its one-use proof cross this
/// bridge. Account passwords and developer-platform sessions stay in Dart.
class NeteaseLoginCaptcha {
  static const channel = MethodChannel('mcdev_income/login_captcha');

  static Future<String?> verify(LoginCaptchaChallenge challenge) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      throw McDevException(
        '当前平台暂未提供网易验证码窗口，请使用 macOS 桌面端完成登录',
        Uri.https('dl.reg.163.com', '/'),
      );
    }
    final random = Random.secure();
    final nonce = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    try {
      final proof = await channel.invokeMethod<String>('verify', {
        'html': buildPage(challenge, nonce: nonce),
        'nonce': nonce,
      });
      if (proof != null && (proof.trim().isEmpty || proof.length > 16384)) {
        throw const FormatException('Invalid captcha proof');
      }
      return proof;
    } on MissingPluginException {
      throw McDevException('验证码窗口未安装，请更新桌面应用后重试', Uri());
    } on PlatformException catch (error) {
      throw McDevException(error.message ?? '验证码窗口打开失败，请重试', Uri());
    }
  }

  @visibleForTesting
  static String buildPage(
    LoginCaptchaChallenge challenge, {
    required String nonce,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(challenge.captchaId) ||
        !const [4, 5, 6].contains(challenge.capFlag) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(nonce)) {
      throw const FormatException('Invalid captcha configuration');
    }
    return _page.replaceFirst(
      '__MCDEV_CONFIG__',
      jsonEncode({
        'captchaId': challenge.captchaId,
        'capFlag': challenge.capFlag,
        'nonce': nonce,
      }),
    );
  }

  // URS uses its own Yidun API/watchman endpoints. These match the official
  // webzj component, rather than the generic public Yidun service defaults.
  static const _page = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' https://*.126.net https://*.127.net https://*.163.com https://*.163yun.com; style-src 'unsafe-inline' https://*.126.net https://*.127.net https://*.163.com https://*.163yun.com; img-src data: blob: https:; connect-src https://*.126.net https://*.127.net https://*.163.com https://*.163yun.com; frame-src https://*.126.net https://*.127.net https://*.163.com https://*.163yun.com; worker-src blob:; font-src data: https://*.126.net https://*.127.net; base-uri 'none'; form-action 'none'">
<title>网易人机验证</title>
<style>
*{box-sizing:border-box}html,body{margin:0;min-height:100%;background:#48494a;color:#f2f2f2;font:16px -apple-system,BlinkMacSystemFont,sans-serif}
main{margin:24px;padding:20px;border:2px solid #141516;background:#5b5d60;box-shadow:inset 2px 2px #7b7d80,0 4px #141516}
h1{font-size:22px;margin:0 0 12px}p{line-height:1.5;margin:10px 0}#status{min-height:48px;color:#f2f2f2}
#captchaHost{width:320px;min-height:140px;margin:16px auto;max-width:100%}
nav{display:flex;gap:12px;flex-wrap:wrap;margin-top:20px}
button{font:inherit;padding:10px 16px;border:2px solid #141516;border-radius:0;background:#d0d1d4;color:#141516;box-shadow:inset 2px 2px #f2f2f2,0 3px #141516;cursor:pointer}
button:active{box-shadow:inset 2px 2px #8c8e91;transform:translateY(2px)}button:disabled{opacity:.55;cursor:wait}
#verify{background:#3c8527;color:#fff;box-shadow:inset 2px 2px #6bb452,0 3px #141516}#verify:hover{background:#2a641c}#verify:active{background:#1d4d13}
</style></head><body><main>
<h1>网易人机验证</h1><p>请完成官方验证，验证通过后会自动继续登录。</p>
<p id="status" role="status" aria-live="polite">正在加载验证码…</p>
<div id="captchaHost"></div>
<nav><button id="verify" disabled>开始验证</button><button id="reload">重新加载</button><button id="cancel">取消</button></nav>
</main><script>
(function(){'use strict';
  const config=__MCDEV_CONFIG__;
  const status=document.getElementById('status');
  const verify=document.getElementById('verify');
  let instance=null,finished=false;
  function send(type,fields){
    if(window.webkit&&window.webkit.messageHandlers.mcdevCaptcha){
      window.webkit.messageHandlers.mcdevCaptcha.postMessage(Object.assign({type:type,nonce:config.nonce},fields||{}));
    }
  }
  function ready(value){
    if(value)instance=value;
    verify.disabled=!instance;
    status.textContent=config.capFlag===6?'请点击“开始验证”，按提示完成操作。':'请完成下方验证码。';
  }
  function failed(){status.textContent='验证码加载失败，请点击“重新加载”重试。';verify.disabled=true;}
  function init(){
    const options={
      captchaId:config.captchaId,element:'#captchaHost',width:320,
      mode:config.capFlag===6?'bind':'embed',lang:'zh-CN',timeout:20000,
      feedbackEnable:false,
      wmServerConfig:{configServer:'webzjac.reg.163.com',apiServer:'webzjac.reg.163.com',staticServer:'acstatic-dun.126.net'},
      apiServer:['webzjcaptcha.reg.163.com','c.dun.163yun.com'],
      staticServer:['cstaticdun.126.net'],
      onReady:ready,
      onVerify:function(error,data){
        if(error){status.textContent='验证未通过，请按提示重试。';return;}
        if(!finished&&data&&typeof data.validate==='string'&&data.validate.length>0&&data.validate.length<=16384){
          finished=true;verify.disabled=true;status.textContent='验证通过，正在继续登录…';
          send('verified',{validate:data.validate});
        }
      },
      onClose:function(){if(!finished)status.textContent='验证已关闭，可点击“开始验证”重试。';}
    };
    if(config.capFlag!==6)options.captchaType=config.capFlag===4?2:3;
    else options.popupStyles={width:350,capBarHeight:40,capPadding:10};
    try{window.initNECaptcha(options,ready,failed);}catch(error){failed();}
  }
  verify.hidden=config.capFlag!==6;
  verify.onclick=function(){if(instance&&!finished)instance.verify();};
  document.getElementById('reload').onclick=function(){send('reload');};
  document.getElementById('cancel').onclick=function(){send('cancel');};
  function load(index){
    const urls=['https://cstaticdun.126.net/load.min.js','https://cstaticdun1.126.net/load.min.js'];
    if(index>=urls.length){failed();return;}
    const script=document.createElement('script');script.src=urls[index];
    script.onload=function(){if(typeof window.initNECaptcha==='function')init();else load(index+1);};
    script.onerror=function(){load(index+1);};document.head.appendChild(script);
  }
  send('opened');load(0);
})();
</script></body></html>''';
}
