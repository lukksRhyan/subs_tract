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
  final _jsonTextController = TextEditingController(); // Novo Controller

  @override
  void dispose() {
    _jsonTextController.dispose(); // Limpa o controller
    super.dispose();
  }

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
        final String originalAssFinalPath = '$videoDir/${baseName}_original_extraida.ass'; // Novo: Caminho para salvar o .ass original
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

        // Novo: Salva uma cópia do .ass original extraído para o usuário
        await File(assOutputPath).copy(originalAssFinalPath);

        setState(() {
          _status =
              'Arquivos gerados com sucesso!\n\n'
              'Original .ass: $originalAssFinalPath\n'
              'JSON para traduzir: $_generatedJsonPath\n\n'
              'IMPORTANTE: Ao traduzir o JSON, mantenha as tags de estilo (ex: {\\pos(1,1)} ou {\\b1}) intactas, traduzindo apenas o texto.\n\n'
              '...e use o próximo passo.';
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
        // Chama a função que lê o arquivo e depois a de reconstrução
        await _rebuildAndEmbedSubtitlesFromFile(translatedJsonPath);
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

  // Nova Função (2b): Processar o JSON colado da caixa de texto
  Future<void> _processPastedJson() async {
    setState(() {
      _isLoading = true;
      _status = '4/5 - Lendo JSON colado e recriando legenda .ass...';
      _progress = 0.75;
    });

    try {
      final String pastedContent = _jsonTextController.text;
      if (pastedContent.trim().isEmpty) {
        throw Exception('A caixa de texto está vazia.');
      }
      
      final List<dynamic> translatedDialogues = jsonDecode(pastedContent);
      
      // Chama a função de reconstrução central
      await _performFinalRebuild(translatedDialogues);

    } catch (e) {
       setState(() {
        _status = 'Erro ao processar o JSON colado: $e';
        _isLoading = false;
      });
    }
  }

  // Função refatorada: apenas lê o arquivo e chama a reconstrução
  Future<void> _rebuildAndEmbedSubtitlesFromFile(String translatedJsonPath) async {
    try {
      setState(() { _status = '4/5 - Lendo JSON e recriando legenda .ass...'; });
      _progress = 0.8;

      final String translatedJsonContent = await File(translatedJsonPath).readAsString();
      final List<dynamic> translatedDialogues = jsonDecode(translatedJsonContent);

      // Chama a função de reconstrução central
      await _performFinalRebuild(translatedDialogues);
    } catch (e) {
       setState(() {
        _status = 'Erro ao ler ou processar o arquivo JSON: $e';
        _isLoading = false;
      });
    }
  }

  // Nova Função Central: Contém toda a lógica de reconstrução
  Future<void> _performFinalRebuild(List<dynamic> translatedDialogues) async {
    // Esta função assume que _isLoading já é true e _progress foi definido
    try {
      final Directory tempDir = await getApplicationDocumentsDirectory();
      final String baseName = p.basenameWithoutExtension(_originalVideoPath!);
      final String originalAssPath = '${tempDir.path}/$baseName.ass';
      final String translatedAssPath = '${tempDir.path}/${baseName}_translated.ass';

      // Carrega as falas traduzidas (agora passadas como parâmetro)
      setState(() { _status = '4/5 - Recriando legenda .ass...'; });

      // Recria o arquivo .ass com as falas traduzidas
      final File originalAssFile = File(originalAssPath);
      final List<String> originalLines = await originalAssFile.readAsLines();
      final List<String> newAssLines = [];
      bool inEventsSection = false;
      int dialogueIndex = 0;
// ... (toda a lógica de 'for (final line in originalLines) ...' permanece a mesma) ...
      for (final line in originalLines) {
        if (line.trim() == '[Events]') {
          inEventsSection = true;
          newAssLines.add(line);
          continue;
        }

        if (inEventsSection && line.startsWith('Dialogue:')) {
          final parts = line.split(',');
          if (dialogueIndex < translatedDialogues.length) {
            // Temos uma tradução para esta linha
            String translatedText = translatedDialogues[dialogueIndex].toString().replaceAll('\n', '\\N');
            final newLine = '${parts.sublist(0, 9).join(',')},$translatedText';
            newAssLines.add(newLine);
          } else {
            // Acabaram as traduções, insere uma linha de diálogo vazia
            final newLine = '${parts.sublist(0, 9).join(',')},';
            newAssLines.add(newLine);
          }
          dialogueIndex++; // IMPORTANTE: Incrementar para *cada* linha de diálogo
        } else {
          newAssLines.add(line);
        }
      }

      await File(translatedAssPath).writeAsString(newAssLines.join('\n'));
      
// ... (toda a lógica de 'FilePicker.platform.getDirectoryPath' permanece a mesma) ...
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
// ... (toda a lógica do comando FFmpeg permanece a mesma) ...
      _finalVideoPath = '$outputDirectory/${baseName}_traduzido.mkv';

      // Comando FFmpeg para criar o vídeo final
      setState(() {
        _status = '5/5 - Criando o vídeo final com a nova legenda... Isso pode demorar.';
        _progress = 0.9;
      });
      
     final ffmpegResult = await Process.run('ffmpeg', [
  '-y',
  '-i', _originalVideoPath!,   // Input 0
  '-i', translatedAssPath,     // Input 1

  // Mapeamentos explícitos
  '-map', '0:v',
  '-map', '0:a',
  '-map', '1:s',
  '-map', '0:s?',

  // Codecs
  '-c:v', 'copy',
  '-c:a', 'copy',
  '-c:s', 'copy',
  '-c:s:0', 'ass',             // Garante que a nova legenda é .ass

  // Metadados (stream 2 geralmente é a nova legenda)
  '-metadata:s:2', 'language=por',
  '-metadata:s:2', 'title=PT-BR',
  '-disposition:s:2', 'default',

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
              const SizedBox(height: 15),
              const Text(
                '...ou cole o conteúdo do JSON traduzido abaixo:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _jsonTextController,
                maxLines: 5,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Conteúdo do JSON traduzido',
                  hintText: '[ "Olá", "Mundo", "Exemplo de JSON"... ]',
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.1),
                ),
                enabled: !_isLoading && _originalVideoPath != null,
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 16),
                  backgroundColor: Colors.green[700],
                ),
                icon: const Icon(Icons.paste),
                label: const Text('2. Finalizar com Texto Colado'),
                onPressed: _isLoading || _originalVideoPath == null
                    ? null
                    : _processPastedJson,
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





