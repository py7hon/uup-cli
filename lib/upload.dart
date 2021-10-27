import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:mime_type/mime_type.dart';
import 'package:uuid/uuid.dart';
import 'package:uup_cli/ansi_pens.dart';
import 'package:uup_cli/encrypt_block_stream.dart';
import 'package:uup_cli/const.dart';


void startEncryptAndUpload(
  File file,
) async {

  Codec<String, String> stringToBase64 = utf8.fuse(base64);

  // Choose the cipher
  final cipher = CipherWithAppendedMac(aesCtr, Hmac(sha256));

  // Choose some 256-bit secret key
  final secretKey = SecretKey.randomBytes(32);

  // Choose some unique (non-secret) nonce (max 16 bytes).
  // The same (secretKey, nonce) combination should not be used twice!
  final nonce = Nonce.randomBytes(16);

  final totalChunks = (file.lengthSync() / (chunkSize + 32)).abs().toInt() + 1;
  
  final uploaderFileId = Uuid().v4();

  final metadata = {
    'aid': uploaderFileId,
    'filename': p.basename(file.path),
    'type': mime(file.path),
    'chunksize': chunkSize,
    'totalchunks': totalChunks,
    'filesize': file.lengthSync(),
  };

  final task = EncryptionUploadTask();

  task.progress.stream.listen((event) {
    print(event);
  });

  final stream = task.encryptStreamInBlocks(
      getStreamOfIOFile(file.openRead()), cipher, secretKey);

  final chunkcIDs =
      await task.uploadChunkedStreamToNFT(file.lengthSync(), stream);

  final links = await cipher.encrypt(
    utf8.encode(json.encode({
      'chunks': chunkcIDs,
      'chunkNonces': task.chunkNonces,
      'metadata': metadata,
    })),
    secretKey: secretKey,
    nonce: nonce,
  );

  String cID;

  while (cID == null) {
    try {
      cID = await task.uploadFileToNFT(links);

      if ((cID ?? '').isEmpty) throw Exception('oops');
    } catch (e, st) {
      print(e);
      print(st);
      print('retry');
    }
  }

  //Encrypt

  final secret =
      base64.encode([...(await secretKey.extract()), ...nonce.bytes]);

  final link = stringToBase64.encode('x-$cID/#$secret');

  print('Secure Download Link for ${greenBold(metadata['filename'])}:');
  print('\nCLI: $link');
  print('\nWeb: https://uup.bugs.today/#x-$cID+$secret');
}

Stream<List<int>> getStreamOfIOFile(Stream<List<int>> stream) async* {
  List<int> tmp = [];

  await for (final element in stream) {
    tmp.addAll(element);

    if (tmp.length >= chunkSize) {
      yield tmp.sublist(0, chunkSize);

      tmp.removeRange(0, chunkSize);
    }
  }
  yield tmp;
}
