import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:uup_cli/ansi_pens.dart';
import 'package:uup_cli/download.dart';
import 'package:uup_cli/upload.dart';
import 'dart:math';
import 'dart:convert';

void main(List<String> args) async {
  if (args.length != 2) {
    exitWithHelp();
  }
  
  Codec<String, String> stringToBase64 = utf8.fuse(base64);

  final command = args.first;

  if (['download', 'dl', 'd', 'down', '-d', '--download'].contains(command)) {
    print('Downloading metadata...');

    String ccID = stringToBase64.decode(args[1]);

    //ccID = ccID.substring(ccID.indexOf('x') + 2);

    final cID = ccID.substring(ccID.indexOf('x-') + 2);
    final key = ccID.substring(ccID.indexOf('/#') + 2);
    //print(cID);
    //print(key);

    final dlTask = DownloadTask();

    dlTask.progress.stream.listen((event) {
      print(event);
    });

    await dlTask.downloadAndDecryptMetadata(
      cID,
      key,
    );

    print(
        'Do you want to download and decrypt ${greenBold(dlTask.metadata["filename"])}? (${magenta(filesize(dlTask.metadata['filesize']))}) [Y/n]');

    final s = stdin.readLineSync();

    if (!['yes', 'ja', 'y', 'Y', ''].contains(s)) {
      print('Aborted.');
      return;
    }

    int fIndex = 0;

    final String filename = dlTask.metadata["filename"];

    final seperator = filename.lastIndexOf('.');

    String name;
    String ext;

    if (seperator == -1) {
      name = filename;
      ext = '';
    } else {
      name = filename.substring(0, seperator);
      ext = filename.substring(seperator);
    }

    File file = File('$name$ext');

    while (file.existsSync()) {
      fIndex++;

      file = File('$name.$fIndex$ext');
    }

    final tmpFile = File('${file.path}.uup');

    final sink = tmpFile.openWrite();

    dlTask.chunkCtrl.stream.listen((event) async {
      if (event == null) {
        await sink.flush();
        await sink.close();
        print('Renaming file...');

        await tmpFile.rename(file.path);

        print('Download successful');
      } else {
        sink.add(event);
      }
    });

    dlTask.downloadAndDecryptFile();
  } else if (['u', 'up', 'upload', 'send', '-u', '--upload'].contains(command)) {
    final file = File(args[1]);

    if (!file.existsSync()) {
      print('File ${file.path} doesn\'t exist');
      exit(2);
    }

    await startEncryptAndUpload(file);
  }
}

void exitWithHelp() {
  print(greenBold('uup CLI v1.9.3'));
  print('\n');
  print('Encrypted and Fully Decentralized File Share.\nUsing IPFS, Store on Filecoin and Ethereum.');

  print('\n');

  print(magenta('uup --upload') + ' path/to/file');
  print(magenta('uup --download') + ' a some random string like '+'eC1RbVZaeFFZb010UTloQVhDdTVEamd...');

  print('\n');
  print(
      'You can also try aliases like ${magenta("u")}, ${magenta("d")}, ${magenta("up")}, ${magenta("down")}, ${magenta("-u")}, ${magenta("--upload")}, ${magenta("-d")}, or ${magenta("--download")}');

  exit(0);
}
