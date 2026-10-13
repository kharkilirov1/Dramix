import 'dart:convert';
import 'dart:math';

/// A minimal HTML shell that embeds the Kodik player in an iframe.
///
/// Kodik's player refuses to run as a top-level document: its own script does
///
///     if (!isIframe() && hostname !== "localhost" && hostname !== "bs-local.com")
///
/// and then hides the player and renders «Извините, но данной страницы не
/// существует». Framed, it plays normally. Verified on device: the same URL
/// fails in Chrome and works inside any iframe, so no third-party wrapper is
/// needed — this file is that wrapper.
String createPlaybackBridgeToken() {
  final random = Random.secure();
  return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
}

/// Accept only envelopes authenticated by the secret held by the main wrapper.
Map<String, dynamic>? decodePlaybackBridge(String raw,
    {required String token, required String sessionId}) {
  if (token.isEmpty || sessionId.isEmpty || raw.length > 16384) return null;
  try {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> || data['token'] != token ||
        data['sessionId'] != sessionId || data['origin'] is! String ||
        data['sequence'] is! int || (data['sequence'] as int) < 1) return null;
    return data;
  } catch (_) {
    return null;
  }
}

String buildWrapperHtml(String playerUrl,
    {String? bridgeToken, String? sessionId}) {
  final safe = playerUrl
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;');
  final progress = bridgeToken == null || sessionId == null
      ? ''
      : '''
<script>
(function(){
  var expectedOrigin = ${jsonEncode(Uri.parse(playerUrl).origin).replaceAll('<', r'\u003c')};
  var token = ${jsonEncode(bridgeToken).replaceAll('<', r'\u003c')};
  var sessionId = ${jsonEncode(sessionId).replaceAll('<', r'\u003c')};
  var sequence = 0;
  var pending = [];
  var bridgeReady = false;
  function send(envelope){
    try {
      if (window.DramixProgress) {
        window.DramixProgress.postMessage(envelope); return true;
      }
      if (bridgeReady && window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('DramixProgress', envelope);
        return true;
      }
    } catch (_) {}
    return false;
  }
  function ready(){
    bridgeReady = true;
    var queue = pending; pending = [];
    queue.forEach(function(envelope){ if (!send(envelope)) pending.push(envelope); });
  }
  window.addEventListener('flutterInAppWebViewPlatformReady', ready);
  window.addEventListener('dramixProgressBridgeReady', ready);
  window.addEventListener('message', function(event){
    var frame = document.getElementById('dramix-player');
    if (!frame || !frame.contentWindow || event.source !== frame.contentWindow || event.origin !== expectedOrigin) return;
    var envelope;
    try {
      envelope = JSON.stringify({token:token, sessionId:sessionId,
        sequence:++sequence, origin:event.origin, payload:event.data});
    } catch (_) { return; }
    if (envelope.length > 16384) return;
    if (!send(envelope) && pending.length < 256) pending.push(envelope);
  });
})();
</script>
''';
  return '''
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>Плеер</title>
<style>
  html, body { margin:0; padding:0; height:100%; background:#000; overflow:hidden; }
  iframe { display:block; width:100%; height:100%; border:0; }
</style>
</head>
<body>
$progress
<iframe
  id="dramix-player"
  src="$safe"
  allow="autoplay; fullscreen; encrypted-media; picture-in-picture"
  allowfullscreen
  referrerpolicy="origin"></iframe>
</body>
</html>
''';
}
