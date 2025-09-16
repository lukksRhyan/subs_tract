import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:subs_tract/utils/subsprocessing.dart';

Future<void> pickFileOrFolder() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['mkv'],
    allowMultiple: false,
  );

  if (result != null) {
    String? filePath = result.files.single.path;
    if (filePath != null) {
      File file = File(filePath);
      if (await file.exists()) {
        print('Arquivo selecionado: $filePath');
        await extrairFalasParaJson(filePath);
      }
    }
  } else {
    // User canceled the picker, now try to pick a directory
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      print('Pasta selecionada: $selectedDirectory');
      Directory directory = Directory(selectedDirectory);
      if (await directory.exists()) {
        await for (var entity in directory.list(recursive: false)) {
          if (entity is File && p.extension(entity.path).toLowerCase() == '.mkv') {
            print('Processando arquivo na pasta: ${entity.path}');
            await extrairFalasParaJson(entity.path);
          }
        }
      }
    } else {
      print('Nenhum arquivo ou pasta selecionado.');
    }
  }
}
