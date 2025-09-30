import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:process_run/shell.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tradutor de Legendas',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = 'Aguardando o arquivo de vídeo...';
  String? _originalVideoPath;
  String? _generatedJsonPath;
  String? _finalVideoPath;
  bool _isLoading = false;
  bool _isJsonReady = false;

  // Mostra um snackbar com uma mensagem para o usuário
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Passo 1: O usuário seleciona um arquivo de vídeo
  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowedExtensions: ['mkv', 'mp4'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _originalVideoPath = result.files.single.path;
        _status = 'Vídeo selecionado. Processando...';
        _isLoading = true;
        _isJsonReady = false;
        _finalVideoPath = null;
        _generatedJsonPath = null;
      });

      await _extractAndParseSubtitles();
    }
  }

  // Passo 2: Extrai a legenda do vídeo e a converte para JSON
  Future<void> _extractAndParseSubtitles() async {
    if (_originalVideoPath == null) return;

    try {
      final Directory tempDir = await getApplicationDocumentsDirectory();
      final String baseName = p.basenameWithoutExtension(_originalVideoPath!);
      final String originalAssPath = '${tempDir.path}/${baseName}_original.ass';
      _generatedJsonPath = '${tempDir.path}/${baseName}_legendas.json';

      // Comando FFmpeg para extrair a primeira trilha de legenda (0:s:0)
      // Nota: Se a legenda em inglês não for a primeira, este mapa pode precisar de ajuste.
      setState(() { _status = '1/5 - Extraindo trilha de legenda (.ass)...'; });
      var shell = Shell();
      await shell.run('ffmpeg -y -i "$_originalVideoPath" -map 0:s:0 -c copy "$originalAssPath"');
      
      final assFile = File(originalAssPath);
      if (!await assFile.exists()) {
        throw Exception('Não foi possível extrair a legenda. O vídeo pode não conter legendas ou o ffmpeg falhou.');
      }
      
      setState(() { _status = '2/5 - Lendo o arquivo .ass...'; });
      final lines = await assFile.readAsLines();
      final List<String> dialogueLines = [];
      
      // A linha de diálogo no formato .ass geralmente começa com "Dialogue: "
      // e o texto é o último campo após 9 vírgulas.
      final dialogueRegex = RegExp(r'^Dialogue: (?:[^,]*,){9}(.*)$');

      for (final line in lines) {
        final match = dialogueRegex.firstMatch(line);
        if (match != null) {
          dialogueLines.add(match.group(1)!);
        }
      }

      if (dialogueLines.isEmpty) {
         throw Exception('Nenhuma fala encontrada no arquivo de legenda .ass.');
      }

      setState(() { _status = '3/5 - Gerando arquivo .json com as falas...'; });
      final jsonFile = File(_generatedJsonPath!);
      await jsonFile.writeAsString(jsonEncode(dialogueLines));

      setState(() {
        _status = 'Arquivo JSON gerado com sucesso em:\n$_generatedJsonPath\n\nAgora, traduza o conteúdo deste arquivo e selecione-o abaixo.';
        _isLoading = false;
        _isJsonReady = true;
      });

    } catch (e) {
      _showMessage('Ocorreu um erro: $e');
      setState(() {
        _status = 'Falha no processo. Por favor, tente novamente.';
        _isLoading = false;
      });
    }
  }

  // Passo 3: O usuário seleciona o arquivo JSON traduzido
  Future<void> _pickTranslatedJson() async {
     final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
       setState(() {
        _isLoading = true;
        _status = 'JSON traduzido selecionado. Processando...';
      });
      await _rebuildAndEmbedSubtitles(result.files.single.path!);
    }
  }

  // Passo 4: Recria o .ass com as falas traduzidas e o incorpora no vídeo final
  Future<void> _rebuildAndEmbedSubtitles(String translatedJsonPath) async {
    try {
      final Directory tempDir = await getApplicationDocumentsDirectory();
      final String baseName = p.basenameWithoutExtension(_originalVideoPath!);
      final String originalAssPath = '${tempDir.path}/${baseName}_original.ass';
      final String translatedAssPath = '${tempDir.path}/${baseName}_translated.ass';
      final Directory finalDir = await getApplicationDocumentsDirectory(); // Ou outro diretório de preferência
      _finalVideoPath = '${finalDir.path}/${baseName}_traduzido.mkv';

      // Carrega as falas traduzidas do JSON
      setState(() { _status = '4/5 - Lendo JSON e recriando legenda .ass...'; });
      final translatedJsonFile = File(translatedJsonPath);
      final List<dynamic> translatedDialogues = jsonDecode(await translatedJsonFile.readAsString());
      
      // Lê o .ass original e substitui as falas
      final originalAssLines = await File(originalAssPath).readAsLines();
      final List<String> newAssLines = [];
      int dialogueIndex = 0;
      final dialogueRegex = RegExp(r'^(Dialogue: (?:[^,]*,){9})(.*)$');

      for (final line in originalAssLines) {
        final match = dialogueRegex.firstMatch(line);
        if (match != null && dialogueIndex < translatedDialogues.length) {
          final lineStart = match.group(1)!;
          final newLine = '$lineStart${translatedDialogues[dialogueIndex]}';
          newAssLines.add(newLine);
          dialogueIndex++;
        } else {
          newAssLines.add(line);
        }
      }

      await File(translatedAssPath).writeAsString(newAssLines.join('\n'));

      // Comando FFmpeg para criar o vídeo final
      // -map 0      -> Mapeia todos os streams do vídeo original (vídeo, áudio, etc.)
      // -map -0:s   -> Desmapeia (remove) todas as legendas do vídeo original
      // -map 1      -> Adiciona o stream do novo arquivo de legenda
      // -c copy     -> Copia os streams de áudio e vídeo sem recodificar (rápido)
      // -c:s ass    -> Define o codec da legenda para 'ass' (bom para .mkv)
      // -metadata:s:s:0 language=por -> Define o idioma da nova legenda
      setState(() { _status = '5/5 - Criando o novo arquivo de vídeo... Isso pode demorar.'; });
      var shell = Shell();
      await shell.run('ffmpeg -y -i "$_originalVideoPath" -i "$translatedAssPath" -map 0 -map -0:s -map 1 -c copy -c:s ass -metadata:s:s:0 language=por "$_finalVideoPath"');
      
      setState(() {
        _status = 'Processo concluído! Seu vídeo com a nova legenda está em:\n$_finalVideoPath';
        _isLoading = false;
        _isJsonReady = false;
      });

    } catch (e) {
      _showMessage('Ocorreu um erro: $e');
      setState(() {
        _status = 'Falha no processo. Por favor, tente novamente.';
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.translate, size: 60, color: Colors.blueAccent),
                const SizedBox(height: 20),
                Text(
                  'Automatize a Tradução de Legendas',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                
                // Botão para Passo 1
                SizedBox(
                  width: 250,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _pickVideo,
                    icon: const Icon(Icons.video_file),
                    label: const Text('1. Selecionar Vídeo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Botão para Passo 2
                SizedBox(
                  width: 250,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || !_isJsonReady ? null : _pickTranslatedJson,
                    icon: const Icon(Icons.file_upload),
                    label: const Text('2. Enviar JSON Traduzido'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                       shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Indicador de progresso e status
                if (_isLoading) const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Status",
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(_status, textAlign: TextAlign.left),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}