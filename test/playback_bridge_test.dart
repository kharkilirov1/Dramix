import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dramix/ui/player/player_wrapper.dart';

void main() {
  test('native bridge rejects spoofed nonces and previous embed sessions', () {
    String envelope(String token, String session) => jsonEncode({
      'token': token, 'sessionId': session, 'sequence': 1,
      'origin': 'https://kodikplayer.com',
      'payload': {'key': 'kodik_player_play'},
    });
    expect(decodePlaybackBridge(envelope('wrong', 'current'),
        token: 'private', sessionId: 'current'), isNull);
    expect(decodePlaybackBridge(envelope('private', 'previous'),
        token: 'private', sessionId: 'current'), isNull);
    expect(decodePlaybackBridge(envelope('private', 'current'),
        token: 'private', sessionId: 'current'), isNotNull);
    expect(decodePlaybackBridge(jsonEncode({
      'sessionId': 'current', 'sequence': 1,
      'origin': 'https://kodikplayer.com',
      'payload': {'key': 'kodik_player_play'},
    }), token: 'private', sessionId: 'current'), isNull);
  });

  test('oversized and invalid bridge payloads fail closed', () {
    expect(decodePlaybackBridge('x' * 20000,
        token: 'private', sessionId: 'current'), isNull);
    expect(decodePlaybackBridge('{',
        token: 'private', sessionId: 'current'), isNull);
    expect(decodePlaybackBridge(jsonEncode({
      'token': 'private', 'sessionId': 'current', 'sequence': -1,
      'origin': 'https://kodikplayer.com',
    }), token: 'private', sessionId: 'current'), isNull);
  });

  test('wrapper values cannot escape inline script or iframe attributes', () {
    final html = buildWrapperHtml(
      'https://kodikplayer.com/video/1?x=</script><img src=x>',
      bridgeToken: '</script><img src=x>',
      sessionId: '</script><img src=x>',
    );
    expect(html, isNot(contains('</script><img')));
    expect(html, contains(r'\u003c/script>'));
    expect(html, contains('&lt;/script>'));
    expect(html.indexOf('window.addEventListener'),
        lessThan(html.indexOf('<iframe')));
  });

  test('bridge tokens are independent per embed lifetime', () {
    final first = createPlaybackBridgeToken();
    final second = createPlaybackBridgeToken();
    expect(base64Url.decode(first), hasLength(32));
    expect(first, isNot(second));
  });
}
