import 'package:http/http.dart' as http;

/// Probe the actual download without fetching a whole APK or sending login tokens.
Future<void> checkReleaseUrl(
  String url,
  int size, {
  http.Client? transport,
}) async {
  final client = transport ?? http.Client();
  try {
    var uri = Uri.parse(url);
    for (var redirects = 0; ; redirects++) {
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('APK 直链及跳转必须使用 HTTPS');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['Range'] = 'bytes=0-3';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (redirects >= 5 || location == null) {
          throw const FormatException('下载地址跳转异常');
        }
        uri = uri.resolve(location);
        continue;
      }
      final type = response.headers['content-type']?.toLowerCase() ?? '';
      if (![200, 206].contains(response.statusCode) ||
          type.contains('text/html') ||
          type.contains('application/json')) {
        await response.stream.listen((_) {}).cancel();
        throw FormatException('地址未返回 APK（HTTP ${response.statusCode}），不能发布');
      }
      if (response.statusCode == 206) {
        final range = RegExp(
          r'^bytes 0-(\d+)/(\d+)$',
        ).firstMatch(response.headers['content-range'] ?? '');
        if (range == null ||
            int.parse(range[2]!) != size ||
            int.parse(range[1]!) >= size) {
          await response.stream.listen((_) {}).cancel();
          throw const FormatException('下载文件大小与发布信息不一致');
        }
      } else if (response.contentLength != null &&
          response.contentLength != size) {
        await response.stream.listen((_) {}).cancel();
        throw const FormatException('下载文件大小与发布信息不一致');
      }
      final header = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        header.addAll(chunk.take(4 - header.length));
        if (header.length == 4) break;
      }
      if (header.length != 4 ||
          header[0] != 80 ||
          header[1] != 75 ||
          header[2] != 3 ||
          header[3] != 4) {
        throw const FormatException('下载内容不是 APK/ZIP 文件，请检查直链');
      }
      return;
    }
  } finally {
    if (transport == null) client.close();
  }
}
