import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huideng_admin/services/release_url_check.dart';

void main() {
  test(
    'publish probe rejects HTML and checks range total without login headers',
    () async {
      final good = MockClient((r) async {
        expect(r.headers['Range'], 'bytes=0-3');
        expect(r.headers.containsKey('authorization'), false);
        return http.Response.bytes(
          [80, 75, 3, 4],
          206,
          headers: {'content-range': 'bytes 0-3/100'},
        );
      });
      await checkReleaseUrl(
        'https://example.test/app.apk',
        100,
        transport: good,
      );
      good.close();
      final html = MockClient(
        (_) async => http.Response(
          '<html>login</html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      );
      await expectLater(
        checkReleaseUrl('https://example.test/login', 100, transport: html),
        throwsFormatException,
      );
      html.close();
    },
  );
}
