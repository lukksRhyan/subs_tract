import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum ProcessingMode {
  singleFile,
  folder,
}

enum JsonInputMethod{
  file,
  pastedText,
  httpRequest
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
  String? _selectedPath;
  String? _generatedJsonPath;
  String? _finalVideoPath;
  double _progress = 0.0;
  final _jsonTextController = TextEditingController(); // Novo Controller

  ProcessingMode _videoInputMode = ProcessingMode.singleFile;
  JsonInputMethod _jsonInputMethod = JsonInputMethod.file;


  @override
  void dispose() {
    _jsonTextController.dispose(); // Limpa o controller
    super.dispose();
  }

  Future<String> _openFolder(String path) async {
    final String folderPath = p.dirname(path);

    try {
      if (Platform.isWindows) {
        // No Windows, 'explorer' abre a pasta
        Process.run('explorer', [folderPath]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [folderPath]);
      } else if (Platform.isMacOS) {
        Process.run('open', [folderPath]);
        setState(() {
          _status = 'Crie vergonha, gasta 5k num aparelho pra tá pirateando...';
        });
      }
      return folderPath;
    } catch (e) {
      setState(() {
        _status = 'Erro ao abrir a pasta: $e';
      });
    }
    return folderPath;
  }

  Future<void>_pickVideo() async{
    try{
      
    FilePickerResult? selectedVideo = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowedExtensions: ['mkv', 'mp4'],
      );
    setState(() {
      _selectedPath = selectedVideo?.files.single.path;
    });
    }catch(e){
      setState(() {
        _status = 'Erro ao selecionar vídeo: $e';
      });
    }
  }

  Future<void>_pickFolder() async{
    try{
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecione a pasta contendo os vídeos',
      );
      setState(() {
        _selectedPath = selectedDirectory;
      });
    }catch(e){
      setState(() {
        _status = 'Erro ao selecionar pasta: $e';
      });
    }


    
  }

  Future<void>_process() async{
    _originalVideoPath = _selectedPath;

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
        final String originalAssFinalPath =
            '$videoDir/${baseName}_original_extraida.ass'; // Novo: Caminho para salvar o .ass original
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
          '0:s:m:language:eng?',
          '-c:s',
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
          throw Exception(
              'FFmpeg falhou ao extrair a legenda: ${ffmpegResult.stderr}');
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
          throw Exception(
              'Nenhuma fala encontrada no arquivo de legenda .ass.');
        }

        final File jsonFile = File(_generatedJsonPath!);
        await jsonFile.writeAsString(jsonEncode(dialogues));

        // Novo: Salva uma cópia do .ass original extraído para o usuário
        await File(assOutputPath).copy(originalAssFinalPath);

        // ABRE A PASTA ONDE O ARQUIVO FOI SALVO
        await _openFolder(originalAssFinalPath);

        setState(() {
          _status = 'Arquivos gerados com sucesso!\n\n'
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

  Future<void> _pickAndProcessFolder() async {
    setState(() {
      _isLoading = true;
      _status = '1/5 - Selecionando pasta de vídeos...';
      _progress = 0.1;
      _generatedJsonPath = null;
      _finalVideoPath = null;
    });

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecione a pasta contendo os vídeos',
      );
      if (selectedDirectory != null) {
        final dir = Directory(selectedDirectory);
        final List<FileSystemEntity> files = dir.listSync();

        final List<File> videoFiles = files.whereType<File>().where((file) {
          final ext = p.extension(file.path).toLowerCase();
          return ext == '.mkv' || ext == '.mp4';
        }).toList();

        if (videoFiles.isEmpty) {
          throw Exception(
              'Nenhum arquivo de vídeo (.mp4 ou .mkv) encontrado na pasta selecionada.');
        }

        int videoCount = 0;
        for (final videoFile in videoFiles) {
          videoCount++;
          final String currentVideoPath = videoFile.path;

          setState(() {
            _status =
                'Processando vídeo $videoCount de ${videoFiles.length}:\n${p.basename(currentVideoPath)}';
            _progress = 0.1 + (videoCount - 1) / videoFiles.length * 0.6;
          });

          // --- INÍCIO DA LÓGICA DE PROCESSAMENTO (MOVIDA PARA DENTRO DO LOOP) ---
          final String videoDir = p.dirname(currentVideoPath);
          final String baseName = p.basenameWithoutExtension(currentVideoPath);
          final Directory tempDir = await getApplicationDocumentsDirectory();
          final String assOutputPath = '${tempDir.path}/$baseName.ass';
          final String originalAssFinalPath =
              '$videoDir/${baseName}_original_extraida.ass';
          final String generatedJsonPathForFile =
              '$videoDir/${baseName}_legendas.json';

          // Tenta extrair a legenda em inglês, se falhar, extrai a primeira disponível.
          var ffmpegResult = await Process.run('ffmpeg', [
            '-y',
            '-i',
            currentVideoPath, // <--- CORRIGIDO
            '-map',
            '0:s:m:language:eng?',
            '-c:s',
            'ass',
            assOutputPath
          ]);

          if (ffmpegResult.exitCode != 0) {
            // Se não encontrar legenda em inglês, tenta a primeira trilha de legenda
            ffmpegResult = await Process.run('ffmpeg', [
              '-y',
              '-i',
              currentVideoPath, // <--- CORRIGIDO
              '-map',
              '0:s:0?',
              '-c:s',
              'ass',
              assOutputPath
            ]);
          }

          if (ffmpegResult.exitCode != 0) {
            // Pula este arquivo, mas não para o lote
            setState(() {
              _status =
                  'Erro ao extrair legenda de ${p.basename(currentVideoPath)}. Pulando...';
            });
            continue; // Pula para o próximo vídeo
          }

          // Ler o arquivo .ass e extrair apenas as falas para o JSON
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
              final parts = line.split(',');
              if (parts.length >= 10) {
                final text = parts.sublist(9).join(',');
                dialogues.add(text.replaceAll('\\N', '\n'));
              }
            }
          }

          if (dialogues.isEmpty) {
            setState(() {
              _status =
                  'Nenhuma legenda encontrada em ${p.basename(currentVideoPath)}. Pulando...';
            });
            continue; // Pula para o próximo vídeo
          }

          final File jsonFile = File(generatedJsonPathForFile); // <--- CORRIGIDO
          await jsonFile.writeAsString(jsonEncode(dialogues));

          // Novo: Salva uma cópia do .ass original extraído para o usuário
          await File(assOutputPath).copy(originalAssFinalPath);
          // --- FIM DA LÓGICA DE PROCESSAMENTO ---
        }

        // Abre a pasta DEPOIS que o lote terminar
        await _openFolder(selectedDirectory);

        setState(() {
          _status = 'Processamento em lote concluído!\n'
              'Foram gerados ${videoFiles.length} arquivos .json e .ass.\n'
              'A pasta foi aberta no seu explorador.';
          _isLoading = false;
          _progress = 1.0;
        });
      } else {
        setState(() {
          _status = 'Seleção de pasta cancelada.';
          _isLoading = false;
          _progress = 0.0;
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Erro ao processar pasta: $e';
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
      setState(() {
        _status = '4/5 - Lendo JSON e recriando legenda .ass...';
      });
      _progress = 0.8;

      final String translatedJsonContent =
          await File(translatedJsonPath).readAsString();
      final List<dynamic> translatedDialogues =
          jsonDecode(translatedJsonContent);

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
      // Correção: _originalVideoPath não pode ser nulo aqui.
      if (_originalVideoPath == null) {
        throw Exception("Caminho do vídeo original não está definido.");
      }

      final Directory tempDir = await getApplicationDocumentsDirectory();
      final String baseName = p.basenameWithoutExtension(_originalVideoPath!);
      final String originalAssPath = '${tempDir.path}/$baseName.ass';
      final String translatedAssPath =
          '${tempDir.path}/${baseName}_translated.ass';

      // Carrega as falas traduzidas (agora passadas como parâmetro)
      setState(() {
        _status = '4/5 - Recriando legenda .ass...';
      });

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
            String translatedText = translatedDialogues[dialogueIndex]
                .toString()
                .replaceAll('\n', '\\N');
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
      setState(() {
        _status = 'Quase lá! Selecione onde salvar o vídeo final.';
      });
      String? outputDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecione a pasta para salvar o vídeo traduzido',
      );

      if (outputDirectory == null) {
        // O usuário cancelou a seleção da pasta
        setState(() {
          _status =
              'Operação cancelada. Você não selecionou uma pasta de destino.';
          _isLoading = false;
        });
        return;
      }
// ... (toda a lógica do comando FFmpeg permanece a mesma) ...
      _finalVideoPath = '$outputDirectory/${baseName}_traduzido.mkv';

      // Comando FFmpeg para criar o vídeo final
      setState(() {
        _status =
            '5/5 - Criando o vídeo final com a nova legenda... Isso pode demorar.';
        _progress = 0.9;
      });

      final ffmpegResult = await Process.run('ffmpeg', [
        '-y',
        '-i', _originalVideoPath!, // Input 0
        '-i', translatedAssPath, // Input 1

        // Mapeamentos explícitos
        '-map', '0:v',
        '-map', '0:a',
        '-map', '1:s', // Mapeia a NOVA legenda (input 1)
        '-map', '0:s?', // Mapeia legendas ANTIGAS (input 0)
        
        // Codecs
        '-c', 'copy', // Copia vídeo, áudio e legendas antigas
        '-c:s:0', 'ass', // Define o codec da NOVA legenda (que agora é s:0)

        // Metadados para a NOVA legenda (s:0)
        '-metadata:s:s:0', 'language=por',
        '-metadata:s:s:0', 'title=PT-BR (Traduzido)',
        '-disposition:s:s:0', 'default',

        _finalVideoPath!
      ]);

      if (ffmpegResult.exitCode != 0) {
        throw Exception(
            'FFmpeg falhou ao criar o vídeo final: ${ffmpegResult.stderr}');
      }

      // Abre a pasta ONDE O VÍDEO FINAL FOI SALVO
      await _openFolder(_finalVideoPath!);

      setState(() {
        _status =
            'Processo concluído com sucesso!\n\nVídeo final salvo em:\n$_finalVideoPath';
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
    // Determina a condição de visibilidade para a animação
    final bool isStep2Visible = !_isLoading && _originalVideoPath != null;

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start, // Alinha os cards no topo
                children: [
                  // --- Card Passo 1 (Sempre visível) ---
                  Container(
                    padding: const EdgeInsets.all(12),
                    width: MediaQuery.of(context).size.width * 0.3,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      border: Border.all(color: Colors.blueAccent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.file_open_outlined,
                          size: 40,
                          color: Colors.blueAccent,
                        ),
                        const Text(
                          'Passo 1',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [

                            Column(
                              children: [
                                IconButton(
                               icon: const Icon(
                                Icons.file_open,
                                size: 50,
                                ),
                              onPressed: _pickVideo,
                                ),
                                const Text("Arquivo"),
                              ],
                            ),
                            
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [

                            IconButton(
                              icon: const Icon(
                                Icons.folder_open,
                                size: 50,
                              ),
                              onPressed: _pickFolder, 
                              ),
                              const Text("Pasta")
                            ],),
                            ],
                        ),
                        SelectableText(
                          
                          (_selectedPath==null)?"Caminho não definido": _selectedPath!
                          
                          ),
                        RadioListTile<ProcessingMode>(
                          title: const Text('Arquivo Único'),
                          value: ProcessingMode.singleFile,
                          groupValue: _videoInputMode,
                          onChanged: _isLoading ? null : (ProcessingMode? value) {
                            if (value != null) {
                              setState(() { _videoInputMode = value; });
                            }
                          },
                        ),
                        RadioListTile<ProcessingMode>(
                          title: const Text('Pasta Inteira'),
                          value: ProcessingMode.folder,
                          groupValue: _videoInputMode,
                          onChanged: _isLoading ? null : (ProcessingMode? value) {
                            if (value != null) {
                              setState(() { _videoInputMode = value; });
                            }
                          },
                        ),
                        
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 15),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                          icon: const Icon(Icons.video_file),
                          // Texto do botão muda baseado no modo
                          label: Text(_videoInputMode == ProcessingMode.singleFile 
                                ? 'Extrair Legenda' 
                                : 'Extrair Legendas da Pasta'),
                          onPressed: _isLoading
                              ? null
                              : () {
                                  if (_videoInputMode == ProcessingMode.singleFile) {
                                    _pickAndProcessVideo();
                                  } else {
                                    _pickAndProcessFolder();
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                  
                  // --- Card Passo 2 (Animado) ---
                  // Envolvemos o segundo container com os widgets de animação
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubic,
                    // Se não for visível, desliza 50% para baixo
                    offset: isStep2Visible ? Offset.zero : const Offset(0.0, 0.5),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      // Se não for visível, fica transparente
                      opacity: isStep2Visible ? 1.0 : 0.0,
                      
                      // Este é o seu container original, AGORA SEM O 'IF'
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        width: MediaQuery.of(context).size.width * 0.3,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          border: Border.all(color: Colors.green, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.translate,
                              size: 40,
                              color: Colors.green,
                            ),
                            const Text(
                              'Passo 2',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            const Text("Métodos para fornecer o JSON traduzido:"),
                            const SizedBox(height: 10),
                            Container(
                              height: 1,
                              color: Colors.green,
                              child: Row(
                                children: [],
                              ),
                            ),
                            ListTile(
                              title: const Text('Arquivo'),
                              leading: Radio<JsonInputMethod>(
                                value: JsonInputMethod.file,
                                groupValue: _jsonInputMethod,
                                onChanged: isStep2Visible ? (JsonInputMethod? value) {
                                  if (value != null) {
                                    setState(() { _jsonInputMethod = value; });
                                  }
                                } : null,
                              ),
                            ),
                            ListTile(
                              title: const Text('Texto'),
                              leading: Radio<JsonInputMethod>(
                                value: JsonInputMethod.pastedText,
                                groupValue: _jsonInputMethod,
                                onChanged: isStep2Visible ? (JsonInputMethod? value) {
                                  if (value != null) {
                                    setState(() { _jsonInputMethod = value; });
                                  }
                                } : null,
                              ),
                            ),
                            const SizedBox(height: 10),

                            if(_jsonInputMethod == JsonInputMethod.file)ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 30, vertical: 15),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              icon: const Icon(Icons.file_upload),
                              label: const Text('Enviar JSON e Finalizar'),

                              
                              // A lógica de 'enabled' é movida para cá
                              onPressed: isStep2Visible 
                                  ? _pickTranslatedJsonAndFinish 
                                  : null,
                            ),
                            
                            const SizedBox(height: 10),
                            if(_jsonInputMethod == JsonInputMethod.pastedText)Column(
                              children: [
                                TextField(
                              controller: _jsonTextController,
                              maxLines: 5,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: 'Conteúdo do JSON',
                                hintText:
                                    '[ "Olá", "Mundo", "Exemplo"... ]',
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.1),
                              ),
                              enabled: isStep2Visible,
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 30, vertical: 15),
                                textStyle: const TextStyle(fontSize: 16),
                                backgroundColor: Colors.green[700],
                              ),
                              icon: const Icon(Icons.paste),
                              label: const Text('Finalizar com Texto'),
                              onPressed: isStep2Visible 
                                  ? _processPastedJson 
                                  : null,
                            ),
                              ],
                            ),
                            
                            
                            
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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
                  style:
                      const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

