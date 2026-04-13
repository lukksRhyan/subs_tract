import 'dart:convert';
import 'dart:io';
import 'package:SubsTract/credit_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/video_metadata.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SubsTract Pro',
      theme: ThemeData(brightness: Brightness.dark, primaryColor: Colors.blueAccent),
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
  String _status = 'Selecione um vídeo para começar.';
  bool _isLoading = false;
  String _apiKey = '';
  
  VideoMetadata? _currentMetadata;
  List<SubtitleTrack> _availableTracks = [];
  SubtitleTrack? _selectedTrack;
  List<String> _extractedDialogues = [];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _episodeController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkFFmpeg();
  }

  Future<void> _checkFFmpeg() async {
    try {
      await Process.run('ffmpeg', ['-version']);
    } catch (_) {
      setState(() => _status = 'Erro: FFmpeg não detectado no sistema.');
    }
  }

  String _cleanJson(String text) {
    String cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
    int start = cleaned.indexOf('[');
    int end = cleaned.lastIndexOf(']');
    return (start != -1 && end != -1) ? cleaned.substring(start, end + 1) : cleaned;
  }

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      final path = result.files.single.path!;
      final meta = VideoMetadata.fromPath(path);
      setState(() {
        _currentMetadata = meta;
        _titleController.text = meta.title;
        _episodeController.text = meta.episode;
        _isLoading = true;
      });
      await _analyzeTracks(path);
    }
  }

  Future<void> _analyzeTracks(String path) async {
    final result = await Process.run('ffprobe', [
      '-v', 'quiet', '-print_format', 'json', '-show_streams', '-select_streams', 's', path
    ]);
    if (result.exitCode == 0) {
      final streams = jsonDecode(result.stdout)['streams'] as List;
      setState(() {
        _availableTracks = streams.map((s) => SubtitleTrack(
          index: s['index'],
          language: s['tags']?['language'] ?? 'und',
          title: s['tags']?['title'],
        )).toList();
        if (_availableTracks.isNotEmpty) _selectedTrack = _availableTracks.first;
        _isLoading = false;
        _status = 'Vídeo carregado.';
      });
    }
  }

  Future<void> _extractToMemory() async {
    if (_currentMetadata == null || _selectedTrack == null) return;
    final tempDir = await getTemporaryDirectory();
    final assPath = p.join(tempDir.path, 'temp.ass');

    await Process.run('ffmpeg', [
      '-y', '-i', _currentMetadata!.filePath,
      '-map', '0:${_selectedTrack!.index}', '-c:s', 'ass', assPath
    ]);

    final lines = await File(assPath).readAsLines();
    _extractedDialogues = [];
    bool inEvents = false;
    for (var line in lines) {
      if (line.trim() == '[Events]') { inEvents = true; continue; }
      if (inEvents && line.startsWith('Dialogue:')) {
        final parts = line.split(',');
        if (parts.length >= 10) _extractedDialogues.add(parts.sublist(9).join(',').replaceAll('\\N', '\n'));
      }
    }
  }

  Future<void> _translateWithGemini() async {
    if (_apiKey.isEmpty) { _showSettings(); return; }
    setState(() { _isLoading = true; _status = 'Extraindo e traduzindo...'; });

    try {
      await _extractToMemory();
      final model = GenerativeModel(model: 'models/gemini-2.5-flash', apiKey: _apiKey);
      
      final prompt = "Translate this anime subtitle JSON array to Brazilian Portuguese. "
          "Keep style tags like {\\pos(x,y)} and line breaks \\N. "
          "Return ONLY the translated JSON array:\n\n"
          "${jsonEncode(_extractedDialogues)}";

      final response = await model.generateContent([Content.text(prompt)]);
      final result = _cleanJson(response.text ?? '');
      
      jsonDecode(result); 
      setState(() { _status = 'Tradução concluída!'; _isLoading = false; });
      _showSuccessDialog(result);
    } catch (e) {
      setState(() { _status = 'Erro Gemini: $e'; _isLoading = false; });
    }
  }

  Future<void> _generateFinalVideo(String translatedJsonStr) async {
    Navigator.pop(context); 
    
    try {
      setState(() {
        _isLoading = true;
        _status = 'Selecione a pasta para salvar o vídeo...';
      });

      String? outputDirectory = await FilePicker.platform.getDirectoryPath();
      if (outputDirectory == null) {
        setState(() {
          _isLoading = false;
          _status = 'Operação cancelada (pasta não selecionada).';
        });
        return;
      }

      setState(() => _status = 'Criando arquivo .ass traduzido...');

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

      final String titleStr = _titleController.text.isNotEmpty ? _titleController.text : 'Traduzido';
      final String epStr = _episodeController.text.isNotEmpty ? '_E${_episodeController.text}' : '';
      final String finalVideoPath = p.join(outputDirectory, '${titleStr}${epStr}_PTBR.mkv');

      setState(() => _status = 'Gerando MKV final... Isso pode demorar, não feche o app.');

      final result = await Process.run('ffmpeg', [
        '-y',
        '-i', _currentMetadata!.filePath,
        '-i', translatedAssPath,
        '-map', '0:v',     
        '-map', '0:a',     
        '-map', '1:s',     
        '-map', '0:s?',    
        '-map', '0:t?',    
        '-c:v', 'copy',
        '-c:a', 'copy',
        '-c:s', 'copy',
        '-c:t', 'copy',
        '-metadata:s:0', 'language=por',
        '-metadata:s:0', 'title=PT-BR',
        '-disposition:s:0', 'default',
        finalVideoPath
      ]);

      if (result.exitCode == 0) {
        setState(() {
          _status = 'Sucesso!\nVídeo salvo em:\n$finalVideoPath';
          _isLoading = false;
        });
      } else {
        throw Exception(result.stderr);
      }
    } catch (e) {
      setState(() {
        _status = 'Erro ao gerar vídeo: $e';
        _isLoading = false;
      });
    }
  }

  void _copyPrompt() async {
    setState(() => _isLoading = true);
    await _extractToMemory();
    final prompt = "Atue como tradutor de animes. Traduza este JSON para PT-BR mantendo as tags. "
        "Responda apenas o JSON:\n\n${jsonEncode(_extractedDialogues)}";
    await Clipboard.setData(ClipboardData(text: prompt));
    setState(() { _isLoading = false; _status = 'Prompt copiado!'; });
  }

  void _copyPix() async{
    final chavePix = "gbagamer27@gmail.com";
    await Clipboard.setData(ClipboardData(text: chavePix));
  }

  void _copyAddress() async{
    final cryptoAddress = "bc1qvhuaekwfkhp39cf3a2etewghxegfhvrjhe2yah";
    await Clipboard.setData(ClipboardData(text: cryptoAddress));

  }

  Future<void> _saveJsonAndOpenFolder() async {
    setState(() => _isLoading = true);
    await _extractToMemory();
    
    String fileName = '${_titleController.text}_E${_episodeController.text}_original.json';
    String? path = await FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: utf8.encode(jsonEncode(_extractedDialogues)),
    );

    if (path != null) {
      setState(() { _isLoading = false; _status = 'JSON salvo!'; });
      final folder = p.dirname(path);
      if (await canLaunchUrl(Uri.directory(folder))) {
        await launchUrl(Uri.directory(folder));
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuração da API'),
        content: TextField(
          controller: _apiKeyController,
          decoration: const InputDecoration(labelText: 'Gemini API Key'),
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
          ElevatedButton(
            onPressed: () {
              setState(() => _apiKey = _apiKeyController.text);
              Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // Função nova para mostrar a Ajuda e os Créditos
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajuda e Créditos'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children:  [
              Text('Como usar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 10),
              Text('1. Selecione um vídeo MKV/MP4 com legenda embutida.'),
              SizedBox(height: 5),
              Text('2. Escolha a trilha de legenda que deseja traduzir.'),
              SizedBox(height: 5),
              Text('3. Ajuste o título e o número do episódio, se necessário.'),
              SizedBox(height: 5),
              Text('4. Escolha seu método de tradução:'),
              Text('   • Automático: Salve sua API Key do Gemini nas configurações e clique em "Traduzir Automaticamente".'),
              Text('   • Manual: Copie o prompt ou salve o arquivo JSON para enviar para outra IA da sua escolha.'),
              SizedBox(height: 5),
              Text('5. Finalize o processo aceitando a geração do vídeo MKV.'),
              SizedBox(height: 20),
              Divider(),
              SizedBox(height: 15),
              Text('Agradecimentos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 5),
              Text('SubsTract Pro v1.0.0'),
              CreditFooter(),
              SizedBox(height: 5),
              Text('Se você pagou por esta aplicação no site dfg.com.br, muito obrigado e espero que goste!'),
              SizedBox(height: 5),
              Text('Caso você tenha obtido de forma gratúita, considere ajudar com qualquer quantia para a evolução deste projeto!'),
              SizedBox(height: 5),
              Row(children: [
                OutlinedButton.icon(
                      icon: const Icon(Icons.currency_exchange),
                      label: const Text('Copiar Pix'),
                      onPressed: _isLoading ? null : _copyPix,
                    ),
                    SizedBox(width: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.currency_bitcoin),
                      label: const Text('Copiar Endereço BTC'),
                      onPressed: _isLoading ? null : _copyAddress,
                    ),
              ],)

            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String content) {
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) => AlertDialog(
        title: const Text('Legendas Traduzidas'),
        content: const Text('A tradução foi concluída com sucesso pela IA. Deseja iniciar a geração do vídeo MKV agora?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => _generateFinalVideo(content), 
            child: const Text('Gerar MKV')
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SubsTract Pro'),
        actions: [
          // Botão de Ajuda adicionado aqui
          IconButton(
            icon: const Icon(Icons.help_outline), 
            tooltip: 'Ajuda e Créditos',
            onPressed: _showHelpDialog,
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key), 
            tooltip: 'Configurações API',
            onPressed: _showSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.video_library),
              label: const Text('Selecionar Vídeo'),
              onPressed: _isLoading ? null : _pickVideo,
            ),
            if (_currentMetadata != null) ...[
              const SizedBox(height: 20),
              DropdownButtonFormField<SubtitleTrack>(
                value: _selectedTrack,
                items: _availableTracks.map((t) => DropdownMenuItem(value: t, child: Text(t.toString()))).toList(),
                onChanged: (v) => setState(() => _selectedTrack = v),
                decoration: const InputDecoration(labelText: 'Trilha de Legenda'),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(flex: 3, child: TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Título'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _episodeController, decoration: const InputDecoration(labelText: 'Ep'))),
                ],
              ),
              const SizedBox(height: 30),
              const Text('OPÇÕES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Traduzir Automaticamente (API)'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: _isLoading ? null : _translateWithGemini,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_all),
                      label: const Text('Copiar Prompt'),
                      onPressed: _isLoading ? null : _copyPrompt,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Salvar e Abrir Pasta'),
                      onPressed: _isLoading ? null : _saveJsonAndOpenFolder,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  if (_isLoading) const Padding(padding: EdgeInsets.only(bottom: 15), child: CircularProgressIndicator()),
                  SelectableText(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}