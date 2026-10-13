import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dramix/core/net.dart';

class _CloseTrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError('This test only exercises client ownership');

  @override
  void close() => closed = true;
}

void main() {
  test('closing a CORS proxy client closes its owned inner client', () {
    final inner = _CloseTrackingClient();
    final client = CorsProxyClient(
      mode: NetMode.wrap,
      template: Net.allOrigins,
      inner: inner,
    );

    expect(inner.closed, isFalse);
    client.close();

    expect(inner.closed, isTrue);
  });
}
