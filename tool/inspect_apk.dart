import 'dart:convert';
import 'dart:io';
import 'package:huideng_admin/services/apk_metadata.dart';

Future<void> main(List<String> args) async {
  final a = await inspectApk(args.single);
  stdout.writeln(
    jsonEncode({
      'versionName': a.versionName,
      'versionCode': a.versionCode,
      'size': a.size,
      'sha256': a.hash,
      'package': a.packageName,
    }),
  );
}
