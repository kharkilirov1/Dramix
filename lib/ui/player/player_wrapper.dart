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
String buildWrapperHtml(String playerUrl) {
  final safe = playerUrl
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;');
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
<iframe
  src="$safe"
  allow="autoplay; fullscreen; encrypted-media; picture-in-picture"
  allowfullscreen
  referrerpolicy="origin"></iframe>
</body>
</html>
''';
}
