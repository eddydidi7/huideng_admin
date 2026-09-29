import 'dart:io';
import 'package:crypto/crypto.dart';
import 'apk_metadata.dart';

/// Computes size + SHA-256 for an arbitrary file (broadcast attachments are
/// not APKs). Reuses ApkMetadata as a plain (path, size, hash) carrier:
/// ReleaseApkUploader.upload() only reads those three fields, never
/// versionName/versionCode/packageName, so this is safe to feed it directly.
Future<ApkMetadata> inspectGenericFile(String path) async {
  final file = File(path);
  final stat = await file.stat();
  if (stat.size < 1) throw const FormatException('文件为空或无法读取');
  final digest = (await sha256.bind(file.openRead()).first).toString();
  final after = await file.stat();
  if (after.size != stat.size || after.modified != stat.modified) {
    throw const FormatException('读取期间文件已改变，请重新选择');
  }
  return ApkMetadata(path, stat.size, digest, '', 0, '');
}
