import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:uup_cli/config.dart';
import 'package:uup_cli/const.dart';
import 'package:uuid/uuid.dart';
import 'package:http_parser/http_parser.dart';

List<String> ipfsGateway = [
  'https://ipfs.io/ipfs/', // FAST and CORS
  'https://cloudflare-ipfs.com/ipfs/', // FAST and CORS, Video Stream not supported
  'https://ipfs.fleek.co/ipfs/', // FAST and CORS
  'https://dweb.link/ipfs/', // FAST and CORS
  'https://ipfs.trusti.id/ipfs/', // FAST and CORS
  'https://ipfs.eu.org/ipfs/', // FAST and CORS
  'http://ipfs.iqbalrifai.eu.org/ipfs/', // FAST, CORS and Host on Bulletproof Server
];

String getRandomGateway() {
  return ipfsGateway[Random().nextInt(ipfsGateway.length)];
}


class EncryptionUploadTask {
  int i = 0;

  Map<String, String> chunkNonces = {};

  void setState(String s) {
    progress.add(s);
  }

  final progress = StreamController<String>.broadcast();

  Stream<List<int>> encryptStreamInBlocks(Stream<List<int>> source,
      CipherWithAppendedMac cipher, SecretKey secretKey) async* {
    i = 0;
    int internalI = 0;

    chunkNonces = {};
    await for (var chunk in source) {
      internalI++;
      while (i < internalI - 3) {
        await Future.delayed(Duration(milliseconds: 20));
      }

      final chunkNonce = Nonce.randomBytes(16);
      chunkNonces[internalI.toString()] = base64.encode(chunkNonce.bytes);

      yield await cipher.encrypt(
        chunk,
        secretKey: secretKey,
        nonce: chunkNonce,
      );
    }
  }

  Future<List<String>> uploadChunkedStreamToNFT(
      int fileSize, Stream<List<int>> byteUploadStream) async {
    final totalChunks = (fileSize / (chunkSize + 32)).abs().toInt() + 1;

    print('Total chunks: $totalChunks');

    final uploaderFileId = Uuid().v4();
    print('Your Anon Upload ID: $uploaderFileId');

    setState('Encrypting and uploading file... (Chunk 1 of $totalChunks)');

    List<String> cIDs = List.generate(totalChunks, (index) => null);

    _uploadChunk(final Uint8List chunk, final int currentI) async {

      String cID;

      while (cID == null) {
        try {
          cID = await uploadFileToNFT(chunk);

          if ((cID ?? '').isEmpty) throw Exception('oops');
        } catch (e, st) {
          print(e);
          print(st);
          print('retry');
        }
      }

      cIDs[currentI] = cID;
      i++;

      setState(
          'Encrypting and uploading file... ($i/$totalChunks Chunks done)');
    }

    int internalI = 0;
    await for (final chunk in byteUploadStream) {

      _uploadChunk(chunk, internalI);

      while (i < internalI - 2) {
        await Future.delayed(Duration(milliseconds: 20));
      }
      internalI++;
    }

    while (true) {
      await Future.delayed(Duration(milliseconds: 20));
      bool notASingleNull = true;

      for (final val in cIDs) {
        if (val == null) {
          notASingleNull = false;
          break;
        }
      }
      if (notASingleNull) break;
    }
    return cIDs;
  }

  Future<String> uploadFileToNFT(List<int> chunk) async {
    var byteStream = new http.ByteStream.fromBytes(chunk);

    var uri = Uri.parse('https://api.nft.storage/upload');
    //var uri = Uri.parse('https://api.web3.storage/upload');

    var request = new http.MultipartRequest("POST", uri);

    var multipartFile = new http.MultipartFile(
      'file',
      byteStream,
      chunk.length,
      filename: 'uup',
      contentType: MediaType('application', 'octet-stream'),
    );
    request.headers['authorization'] = 'Bearer ${API.KEY}';
    //request.headers['x-name'] = 'blob';
    request.files.add(multipartFile);

    var response = await request.send();

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final res = await response.stream.transform(utf8.decoder).join();

    final resData = json.decode(res);
    final iD = resData['value'];

    if (iD['cid'] == null) throw Exception('Upload Gagal');

    return iD['cid'];
  }
}
