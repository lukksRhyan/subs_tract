import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/video_metadata.dart';

class FFmpegService {
  static Future<bool> isFFmpegInstalled() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<List<SubtitleTrack>> analyzeTracks(String videoPath) async {
    final result = await Process.run('ffprobe', [
      '-v', 'quiet', '-print_format', 'json', '-show_streams', '-select_streams', 's', videoPath
    ]);
    
    if (result.exitCode == 0) {
      final streams = jsonDecode(result.stdout)['streams'] as List;
      return streams.map((s) => SubtitleTrack(
        index: s['index'],
        language: s['tags']?['language'] ?? 'und',
        title: s['tags']?['title'],
      )).toList();
    }
    throw Exception('Falha ao analisar trilhas do vídeo.');
  }

  static Future<List<String>> extractSubtitlesToMemory(String videoPath, int trackIndex) async {
    final tempDir = await getTemporaryDirectory();
    final assPath = p.join(tempDir.path, 'temp.ass');

    await Process.run('ffmpeg', [
      '-y', '-i', videoPath,
      '-map', '0:$trackIndex', '-c:s', 'ass', assPath
    ]);

    final lines = await File(assPath).readAsLines();
    List<String> extractedDialogues = [];
    bool inEvents = false;
    
    for (var line in lines) {
      if (line.trim() == '[Events]') { inEvents = true; continue; }
      if (inEvents && line.startsWith('Dialogue:')) {
        final parts = line.split(',');
        if (parts.length >= 10) {
          extractedDialogues.add(parts.sublist(9).join(',').replaceAll('\\N', '\n'));
        }
      }
    }
    return extractedDialogues;
  }

  static Future<String> generateFinalVideo({
    required String originalVideoPath,
    required String translatedJsonStr,
    required String outputDirectory,
    required String titleStr,
    required String epStr,
    required Function(String) onProgress,
  }) async {
    onProgress('Criando arquivo .ass traduzido...');
    
    final List<dynamic> translatedDialogues = jsonDecode(translatedJsonStr);
    final tempDir = await getTemporaryDirectory();
    final String originalAssPath = p.join(tempDir.path, 'temp.ass');
    final String translatedAssPath = p.join(tempDir.path, 'temp_translated.ass');

    final File originalAssFile = File(originalAssPath);
    final List<String> originalLines = await originalAssFile.readAsLines();
    final List<String> newAssLines = [];
    bool inEventsSection = false;
    int dialogueIndex = 0;

    for (final line in originalLines) {
      if (line.trim() == '[Events]') {
        inEventsSection = true;
        newAssLines.add(line);
        continue;
      }
      if (inEventsSection && line.startsWith('Dialogue:')) {
        final parts = line.split(',');
        if (dialogueIndex < translatedDialogues.length) {
          String text = translatedDialogues[dialogueIndex].toString().replaceAll('\n', '\\N');
          newAssLines.add('${parts.sublist(0, 9).join(',')},$text');
        } else {
          newAssLines.add('${parts.sublist(0, 9).join(',')},');
        }
        dialogueIndex++;
      } else {
        newAssLines.add(line);
      }
    }
    
    await File(translatedAssPath).writeAsString(newAssLines.join('\n'));

    final String finalTitle = titleStr.isNotEmpty ? titleStr : 'Traduzido';
    final String finalEp = epStr.isNotEmpty ? '_E$epStr' : '';
    final String finalVideoPath = p.join(outputDirectory, '$finalTitle$finalEp\_PTBR.mkv');

    onProgress('Gerando MKV final... Isso pode demorar, não feche o app.');

    final result = await Process.run('ffmpeg', [
      '-y', '-i', originalVideoPath, '-i', translatedAssPath,
      '-map', '0:v', '-map', '0:a', '-map', '1:s', '-map', '0:s?', '-map', '0:t?',
      '-c:v', 'copy', '-c:a', 'copy', '-c:s', 'copy', '-c:t', 'copy',
      '-metadata:s:s:0', 'language=por',
      '-metadata:s:s:0', 'title=Português (BR)',
      '-disposition:s:0', 'default',
      '-disposition:s:1', '0', 
      finalVideoPath
    ]);

    if (result.exitCode == 0) {
      return finalVideoPath;
    } else {
      throw Exception(result.stderr);
    }
  }
}