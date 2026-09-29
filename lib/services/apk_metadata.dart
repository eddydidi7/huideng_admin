import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class ApkMetadata {
  ApkMetadata(
    this.path,
    this.size,
    this.hash,
    this.versionName,
    this.versionCode,
    this.packageName,
  );
  final String path, hash, versionName, packageName;
  final int size, versionCode;
}

/// Reads only ZIP directory and AndroidManifest.xml; APK hashing is streamed.
Future<ApkMetadata> inspectApk(String path) async {
  final file = File(path);
  final before = await file.stat();
  if (!path.toLowerCase().endsWith('.apk') ||
      before.size < 22 ||
      before.size > 524288000) {
    throw const FormatException('请选择有效 APK（最大 500 MiB）');
  }
  final r = await file.open();
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > before.size) {
      throw const FormatException('APK 文件不完整');
    }
    await r.setPosition(offset);
    final bytes = await r.read(count);
    if (bytes.length != count) throw const FormatException('APK 读取失败');
    return bytes;
  }

  late Uint8List manifest;
  try {
    final count = before.size < 65557 ? before.size : 65557;
    final tail = await read(before.size - count, count);
    final t = ByteData.sublistView(tail);
    var e = tail.length - 22;
    for (; e >= 0; e--) {
      if (t.getUint32(e, Endian.little) == 0x06054b50 &&
          e + 22 + t.getUint16(e + 20, Endian.little) == tail.length) {
        break;
      }
    }
    if (e < 0 || t.getUint16(e + 4, Endian.little) != 0) {
      throw const FormatException('不是完整的单一 APK');
    }
    final length = t.getUint32(e + 12, Endian.little);
    final offset = t.getUint32(e + 16, Endian.little);
    if (length > 16 * 1024 * 1024) throw const FormatException('APK 目录过大');
    final central = await read(offset, length);
    final d = ByteData.sublistView(central);
    Uint8List? xml;
    for (var p = 0; p + 46 <= central.length;) {
      if (d.getUint32(p, Endian.little) != 0x02014b50) {
        throw const FormatException('APK ZIP 目录损坏');
      }
      final n = d.getUint16(p + 28, Endian.little),
          extra = d.getUint16(p + 30, Endian.little),
          comment = d.getUint16(p + 32, Endian.little);
      final name = utf8.decode(central.sublist(p + 46, p + 46 + n));
      if (name == 'AndroidManifest.xml') {
        final compressed = d.getUint32(p + 20, Endian.little),
            expanded = d.getUint32(p + 24, Endian.little);
        if (compressed > 1024 * 1024 || expanded > 4 * 1024 * 1024) {
          throw const FormatException('APK 清单过大');
        }
        final local = d.getUint32(p + 42, Endian.little);
        final header = ByteData.sublistView(await read(local, 30));
        if (header.getUint32(0, Endian.little) != 0x04034b50) {
          throw const FormatException('APK ZIP 头损坏');
        }
        final raw = await read(
          local +
              30 +
              header.getUint16(26, Endian.little) +
              header.getUint16(28, Endian.little),
          compressed,
        );
        final method = d.getUint16(p + 10, Endian.little);
        if (method == 0) {
          xml = raw;
        } else if (method == 8) {
          final output = BytesBuilder();
          final input = Stream<List<int>>.fromIterable([
            for (var i = 0; i < raw.length; i += 512)
              raw.sublist(i, i + 512 < raw.length ? i + 512 : raw.length),
          ]);
          await for (final chunk in input.transform(ZLibDecoder(raw: true))) {
            if (output.length + chunk.length > 4 * 1024 * 1024) {
              throw const FormatException('APK 清单解压超限');
            }
            output.add(chunk);
          }
          xml = output.takeBytes();
        } else {
          throw const FormatException('不支持的 APK 压缩方式');
        }
        if (xml.length != expanded) throw const FormatException('APK 清单不完整');
        break;
      }
      p += 46 + n + extra + comment;
    }
    if (xml == null) throw const FormatException('APK 缺少 AndroidManifest.xml');
    manifest = xml;
  } finally {
    await r.close();
  }
  final values = parseManifest(manifest);
  final digest = (await sha256.bind(file.openRead()).first).toString();
  final after = await file.stat();
  if (after.size != before.size || after.modified != before.modified) {
    throw const FormatException('读取期间 APK 已改变，请重新选择');
  }
  return ApkMetadata(
    path,
    before.size,
    digest,
    values['versionName']!,
    int.parse(values['versionCode']!),
    values['package']!,
  );
}

Map<String, String> parseManifest(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  int u16(int p) => d.getUint16(p, Endian.little);
  int u32(int p) => d.getUint32(p, Endian.little);
  if (bytes.length < 8 || u16(0) != 3 || u32(4) != bytes.length) {
    throw const FormatException('APK 清单格式无效');
  }
  final strings = <String>[];
  String string(int i) => i < strings.length
      ? strings[i]
      : throw const FormatException('APK 字符索引无效');
  for (var p = u16(2); p + 8 <= bytes.length;) {
    final type = u16(p), header = u16(p + 2), size = u32(p + 4);
    if (size < 8 || p + size > bytes.length) {
      throw const FormatException('APK 清单块损坏');
    }
    if (type == 1) {
      final count = u32(p + 8),
          start = p + u32(p + 20),
          utf = u32(p + 16) & 0x100 != 0;
      if (count > 100000) throw const FormatException('APK 字符串过多');
      for (var i = 0; i < count; i++) {
        var at = start + u32(p + header + i * 4);
        int len8() {
          final a = bytes[at++];
          return a & 0x80 != 0 ? ((a & 0x7f) << 8) | bytes[at++] : a;
        }

        int len16() {
          final a = u16(at);
          at += 2;
          if (a & 0x8000 == 0) return a;
          final b = u16(at);
          at += 2;
          return ((a & 0x7fff) << 16) | b;
        }

        if (utf) {
          len8();
          final n = len8();
          strings.add(utf8.decode(bytes.sublist(at, at + n)));
        } else {
          final n = len16();
          strings.add(
            String.fromCharCodes([for (var j = 0; j < n; j++) u16(at + j * 2)]),
          );
        }
      }
    } else if (type == 0x102 && string(u32(p + 20)) == 'manifest') {
      final out = <String, String>{};
      final count = u16(p + 28),
          stride = u16(p + 26),
          start = p + 16 + u16(p + 24);
      if (stride < 20) throw const FormatException('APK 属性损坏');
      for (var i = 0; i < count; i++) {
        final a = start + i * stride,
            key = string(u32(a + 4)),
            raw = u32(a + 8),
            kind = bytes[a + 15],
            value = u32(a + 16);
        if (['package', 'versionName', 'versionCode'].contains(key)) {
          out[key] = raw != 0xffffffff
              ? string(raw)
              : kind == 3
              ? string(value)
              : value.toString();
        }
        if (key == 'versionCodeMajor' && value != 0) {
          throw const FormatException('暂不支持超大 versionCode');
        }
      }
      if (out['package'] == null ||
          out['versionName'] == null ||
          (int.tryParse(out['versionCode'] ?? '') ?? 0) <= 0) {
        throw const FormatException('无法读取 APK 版本号');
      }
      return out;
    }
    p += size;
  }
  throw const FormatException('APK 缺少版本信息');
}
