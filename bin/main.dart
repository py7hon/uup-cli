import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:uup_cli/ansi_pens.dart';
import 'package:uup_cli/download.dart';
import 'package:uup_cli/upload.dart';


void main(List<String> args) async {
  if (args.length != 2) {
    exitWithHelp();
  }

  final command = args.first;

  if (['download', 'dl', 'd', 'down', '-d', '--download'].contains(command)) {
    print('Downloading metadata...');

    String hash = args[1];

    hash = hash.substring(hash.indexOf('#') + 1);

    if (hash.startsWith(RegExp(r'[0-9]'))) {
      print('Unsupported version. Please use the Web UI.');
      return;
    }

    final lengthSep = hash.indexOf('-');

    final version = hash.substring(0, lengthSep);
    if (version == 'a') {
      print('Unsupported version. Please use the Web UI.');
      return;
    }

    hash = hash.substring(lengthSep + 1);

    final sep = hash.indexOf('+');

    final cID = hash.substring(0, sep);
    final key = hash.substring(sep + 1);

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
  print(greenBold('uup CLI v1'));

  print('\n');

  print(magenta('uup --upload') + ' path/to/file');
  print(magenta('uup --download') + ' https://uup.bugs.today/#x-...');

  print('\n');
  print(
      'You can also try aliases like ${magenta("u")}, ${magenta("d")}, ${magenta("up")}, ${magenta("down")}, ${magenta("-u")}, ${magenta("--upload")}, ${magenta("-d")}, or ${magenta("--download")}');

  exit(0);
}
