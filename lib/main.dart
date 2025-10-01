import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assistente de Tradução de Legendas',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.dark,
      ),
      home: const SubtitleTranslatorPage(),
    );
  }
}

class SubtitleTranslatorPage extends StatefulWidget {
  const SubtitleTranslatorPage({super.key});

  @override
  State<SubtitleTranslatorPage> createState() => _SubtitleTranslatorPageState();
}

class _SubtitleTranslatorPageState extends State<SubtitleTranslatorPage> {
  String _status = 'Aguardando o início do processo...';
  bool _isLoading = false;
  String? _originalVideoPath;
  String? _generatedJsonPath;
  String? _finalVideoPath;
  double _progress = 0.0;

  // Passo 1: Selecionar vídeo e extrair legendas para .ass e depois .json
  Future<void> _pickAndProcessVideo() async {
    setState(() {
      _isLoading = true;
      _status = '1/5 - Selecionando arquivo de vídeo...';
      _progress = 0.1;
      _generatedJsonPath = null;
      _finalVideoPath = null;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowedExtensions: ['mkv', 'mp4'],
      );

      if (result != null) {
        _originalVideoPath = result.files.single.path!;
        final String videoDir = p.dirname(_originalVideoPath!);
        final String baseName = p.basenameWithoutExtension(_originalVideoPath!);
        final Directory tempDir = await getApplicationDocumentsDirectory();
        final String assOutputPath = '${tempDir.path}/$baseName.ass';
        _generatedJsonPath = '$videoDir/${baseName}_legendas.json';

        // Comando FFmpeg para extrair a primeira trilha de legenda em inglês
        setState(() {
          _status = '2/5 - Extraindo legenda (.ass) com FFmpeg...';
          _progress = 0.25;
        });

        // Tenta extrair a legenda em inglês, se falhar, extrai a primeira disponível.
        var ffmpegResult = await Process.run('ffmpeg', [
          '-y',
          '-i',
          _originalVideoPath!,
          '-map',
          '0:s:m:language:eng?','-c:s',
          'ass',
          assOutputPath
        ]);
        
        if (ffmpegResult.exitCode != 0) {
           // Se não encontrar legenda em inglês, tenta a primeira trilha de legenda
           ffmpegResult = await Process.run('ffmpeg', [
            '-y',
            '-i',
            _originalVideoPath!,
            '-map',
            '0:s:0?',
            '-c:s',
            'ass',
            assOutputPath
          ]);
        }

        if (ffmpegResult.exitCode != 0) {
          throw Exception('FFmpeg falhou ao extrair a legenda: ${ffmpegResult.stderr}');
        }

        // Ler o arquivo .ass e extrair apenas as falas para o JSON
        setState(() {
          _status = '3/5 - Processando .ass e gerando .json...';
          _progress = 0.5;
        });

        final File assFile = File(assOutputPath);
        final List<String> lines = await assFile.readAsLines();
        final List<String> dialogues = [];
        bool inEventsSection = false;

        for (final line in lines) {
          if (line.trim() == '[Events]') {
            inEventsSection = true;
            continue;
          }
          if (inEventsSection && line.startsWith('Dialogue:')) {
            // Ex: Dialogue: 0,0:00:01.81,0:00:03.54,Default,,0,0,0,,{\pos(480,517)}Hello, world.
            final parts = line.split(',');
            if (parts.length >= 10) {
              final text = parts.sublist(9).join(',');
              dialogues.add(text.replaceAll('\\N', '\n'));
            }
          }
        }

        if (dialogues.isEmpty) {
          throw Exception('Nenhuma fala encontrada no arquivo de legenda .ass.');
        }

        final File jsonFile = File(_generatedJsonPath!);
        await jsonFile.writeAsString(jsonEncode(dialogues));

        setState(() {
          _status =
              'Arquivo JSON gerado com sucesso!\n\nAgora, traduza este arquivo:\n$_generatedJsonPath\n\n...e use o próximo passo.';
          _progress = 0.7;
          _isLoading = false;
        });
      } else {
        // O usuário cancelou
        setState(() {
          _status = 'Seleção de vídeo cancelada.';
          _isLoading = false;
          _progress = 0.0;
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Erro no Passo 1: $e';
        _isLoading = false;
        _progress = 0.0;
      });
    }
  }

  // Passo 2: Pegar o JSON traduzido e remontar o vídeo
  Future<void> _pickTranslatedJsonAndFinish() async {
    setState(() {
      _isLoading = true;
      _status = 'Selecionando arquivo .json traduzido...';
      _progress = 0.75;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        final String translatedJsonPath = result.files.single.path!;
        await _rebuildAndEmbedSubtitles(translatedJsonPath);
      } else {
        setState(() {
          _status = 'Seleção de JSON cancelada.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Erro no Passo 2: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _rebuildAndEmbedSubtitles(String translatedJsonPath) async {
    try {
      final Directory tempDir = await getApplicationDocumentsDirectory();
      final String baseName = p.basenameWithoutExtension(_originalVideoPath!);
      final String originalAssPath = '${tempDir.path}/$baseName.ass';
      final String translatedAssPath = '${tempDir.path}/${baseName}_translated.ass';

      // Carrega as falas traduzidas do JSON
      setState(() { _status = '4/5 - Lendo JSON e recriando legenda .ass...'; });
      _progress = 0.8;

      final String translatedJsonContent = await File(translatedJsonPath).readAsString();
      final List<dynamic> translatedDialogues = jsonDecode(translatedJsonContent);

      // Recria o arquivo .ass com as falas traduzidas
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
          if (dialogueIndex < translatedDialogues.length) {
            final parts = line.split(',');
            final originalText = parts.sublist(9).join(',');
            String translatedText = translatedDialogues[dialogueIndex].toString().replaceAll('\n', '\\N');
            final newLine = '${parts.sublist(0, 9).join(',')},$translatedText';
            newAssLines.add(newLine);
            dialogueIndex++;
          } else {
            newAssLines.add(line); // Mantém a linha original se não houver tradução
          }
        } else {
          newAssLines.add(line);
        }
      }

      await File(translatedAssPath).writeAsString(newAssLines.join('\n'));
      
      // Novo passo: Pedir ao usuário para selecionar a pasta de destino
      setState(() { _status = 'Quase lá! Selecione onde salvar o vídeo final.'; });
      String? outputDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecione a pasta para salvar o vídeo traduzido',
      );

      if (outputDirectory == null) {
        // O usuário cancelou a seleção da pasta
        setState(() {
          _status = 'Operação cancelada. Você não selecionou uma pasta de destino.';
          _isLoading = false;
        });
        return;
      }
      
      _finalVideoPath = '$outputDirectory/${baseName}_traduzido.mkv';

      // Comando FFmpeg para criar o vídeo final
      setState(() {
        _status = '5/5 - Criando o vídeo final com a nova legenda... Isso pode demorar.';
        _progress = 0.9;
      });
      
      final ffmpegResult = await Process.run('ffmpeg', [
        '-y',
        '-i',
        _originalVideoPath!,
        '-i',
        translatedAssPath,
        '-map', '0',      // Mapeia todos os streams do vídeo original (vídeo, áudio, etc.)
        '-map', '-0:s',    // Desmapeia (remove) todas as legendas do vídeo original
        '-map', '1',       // Mapeia o novo arquivo de legenda
        '-c', 'copy',      // Copia os streams de vídeo e áudio sem re-codificar (rápido)
        '-c:s', 'ass',     // Define o codec da nova legenda
        '-metadata:s:s:0', 'language=por', // Define o idioma da nova legenda como Português
        '-disposition:s:0', 'default',
        _finalVideoPath!
      ]);

      if (ffmpegResult.exitCode != 0) {
        throw Exception('FFmpeg falhou ao criar o vídeo final: ${ffmpegResult.stderr}');
      }

      setState(() {
        _status = 'Processo concluído com sucesso!\n\nVídeo final salvo em:\n$_finalVideoPath';
        _isLoading = false;
        _progress = 1.0;
      });

    } catch (e) {
       setState(() {
        _status = 'Erro ao reconstruir o vídeo: $e';
        _isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistente de Tradução de Legendas'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'Bem-vindo!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Siga os passos para traduzir a legenda do seu vídeo.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                icon: const Icon(Icons.video_file),
                label: const Text('1. Selecionar Vídeo e Extrair Legenda'),
                onPressed: _isLoading ? null : _pickAndProcessVideo,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                icon: const Icon(Icons.translate),
                label: const Text('2. Enviar JSON Traduzido e Finalizar'),
                onPressed: _isLoading || _originalVideoPath == null
                    ? null
                    : _pickTranslatedJsonAndFinish,
              ),
              const SizedBox(height: 40),
              if (_isLoading)
                Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 10),
                  ],
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

