import 'dart:convert';
import 'dart:io';
import 'package:SubsTract/utils.dart/json_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/video_metadata.dart';
import '../services/ffmpeg_service.dart';
import '../services/gemini_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = 'Selecione um vídeo ou uma pasta para começar.';
  bool _isLoading = false;
  String _apiKey = '';
  
  // Modo Unitário
  VideoMetadata? _currentMetadata;
  List<SubtitleTrack> _availableTracks = [];
  SubtitleTrack? _selectedTrack;
  
  // Modo em Lote
  bool _isBatchMode = false;
  List<VideoMetadata> _batchVideos = [];
  String? _batchOutputDir; // Memoriza a pasta de destino do lote

  final _titleController = TextEditingController();
  final _episodeController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _pasteController = TextEditingController(); 

  @override
  void initState() {
    super.initState();
    _initChecks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _episodeController.dispose();
    _apiKeyController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _initChecks() async {
    bool hasFfmpeg = await FFmpegService.isFFmpegInstalled();
    if (!hasFfmpeg) setState(() => _status = 'Erro: FFmpeg não detectado no sistema.');
  }

  void _updateStatus(String msg) {
    if (mounted) setState(() => _status = msg);
  }

  // Descobre a pasta de saída (pede ao usuário apenas na primeira vez se for lote)
  Future<String?> _resolveOutputDir() async {
    if (_isBatchMode) {
      if (_batchOutputDir != null) return _batchOutputDir;
      _batchOutputDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Onde deseja salvar os arquivos deste lote?');
      return _batchOutputDir;
    } else {
      return await FilePicker.platform.getDirectoryPath(dialogTitle: 'Onde salvar o vídeo traduzido?');
    }
  }

  // --- NÚCLEO DE TRADUÇÃO (Serve tanto para Lote quanto Unitário) ---
  Future<void> _saveAndGenerate(VideoMetadata video, String jsonStr, String outDir) async {
    String epStr = video.episode.isNotEmpty ? '_E${video.episode}' : '';
    
    // Salva o JSON traduzido para segurança/backup na mesma pasta
    String jsonSavePath = p.join(outDir, '${video.title}$epStr\_PTBR.json');
    await File(jsonSavePath).writeAsString(jsonStr);
    
    // Gera o MKV
    await FFmpegService.generateFinalVideo(
      originalVideoPath: video.filePath,
      translatedJsonStr: jsonStr,
      outputDirectory: outDir,
      titleStr: video.title,
      epStr: video.episode,
      onProgress: _updateStatus,
    );
    
    setState(() => video.isTranslated = true);
  }

  Future<void> _processVideoAPI(VideoMetadata video) async {
    if (_apiKey.isEmpty) { _showSettings(); return; }
    
    String? outDir = await _resolveOutputDir();
    if (outDir == null) return;

    setState(() { _isLoading = true; _status = 'Extraindo e traduzindo ${video.fileName}...'; });
    try {
      final dialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, video.selectedTrack!.index);
      final translatedJsonStr = await GeminiService.translateSubtitles(dialogues: dialogues, apiKey: _apiKey);
      
      await _saveAndGenerate(video, translatedJsonStr, outDir);
      setState(() { _isLoading = false; _status = 'Sucesso: ${video.fileName}'; });
    } catch (e) {
      setState(() { _isLoading = false; _status = 'Erro em ${video.fileName}: $e'; });
    }
  }

  void _copyPromptForVideo(VideoMetadata video) async {
    setState(() { _isLoading = true; _status = 'Extraindo para prompt...'; });
    try {
      final dialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, video.selectedTrack!.index);
      final prompt = "Atue como tradutor de animes. Traduza este array JSON para PT-BR mantendo as tags. "
          "MUITO IMPORTANTE: 1. Substitua aspas duplas internas por aspas simples ('). "
          "2. Adicione uma barra extra nas tags de estilo. Ex: {\\pos(x,y)} vira {\\\\pos(x,y)}. "
          "Responda APENAS o JSON:\n\n${jsonEncode(dialogues)}";
          
      await Clipboard.setData(ClipboardData(text: prompt));
      setState(() { _isLoading = false; _status = 'Prompt copiado!'; });
      _showPasteTranslatedJsonDialog(video);
    } catch (e) {
      setState(() { _isLoading = false; _status = 'Erro: $e'; });
    }
  }

  Future<void> _saveOriginalJsonForVideo(VideoMetadata video) async {
    setState(() => _isLoading = true);
    try {
      final dialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, video.selectedTrack!.index);
      
      String? path;
      if (_isBatchMode) {
        String? outDir = await _resolveOutputDir();
        if (outDir == null) { setState(() => _isLoading = false); return; }
        String epStr = video.episode.isNotEmpty ? '_E${video.episode}' : '';
        path = p.join(outDir, '${video.title}$epStr\_original.json');
        await File(path).writeAsString(jsonEncode(dialogues));
      } else {
        path = await FilePicker.platform.saveFile(
          fileName: '${video.title}_E${video.episode}_original.json',
          bytes: utf8.encode(jsonEncode(dialogues)),
        );
      }

      if (path != null) {
        final folder = p.dirname(path);
        if (await canLaunchUrl(Uri.directory(folder))) await launchUrl(Uri.directory(folder));
        setState(() => _isLoading = false);
        _showPasteTranslatedJsonDialog(video);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() { _isLoading = false; _status = 'Erro: $e'; });
    }
  }

  // --- SELEÇÃO DE ARQUIVOS E PASTAS ---
  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      final path = result.files.single.path!;
      final meta = VideoMetadata.fromPath(path);
      setState(() {
        _isBatchMode = false;
        _currentMetadata = meta;
        _titleController.text = meta.title;
        _episodeController.text = meta.episode;
        _isLoading = true;
      });
      
      try {
        _availableTracks = await FFmpegService.analyzeTracks(path);
        if (_availableTracks.isNotEmpty) {
          _selectedTrack = _availableTracks.firstWhere(
            (t) => t.language.toLowerCase().contains('eng') || (t.title?.toLowerCase().contains('eng') ?? false),
            orElse: () => _availableTracks.first
          );
        }
        _updateStatus('Vídeo carregado.');
      } catch (e) {
        _updateStatus('Erro: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickFolderAndAnalyze() async {
    String? dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;

    setState(() {
      _isLoading = true;
      _status = 'Varrendo pasta...';
      _isBatchMode = true;
      _batchOutputDir = null; // Reseta a pasta de saída para o novo lote
      _batchVideos = [];
    });

    try {
      Directory dir = Directory(dirPath);
      List<File> videoFiles = dir.listSync().whereType<File>().where((f) {
        String ext = p.extension(f.path).toLowerCase();
        return ext == '.mkv' || ext == '.mp4';
      }).toList();

      for (var file in videoFiles) {
        final meta = VideoMetadata.fromPath(file.path);
        meta.availableTracks = await FFmpegService.analyzeTracks(file.path);
        
        if (meta.availableTracks.isNotEmpty) {
          meta.selectedTrack = meta.availableTracks.firstWhere(
            (t) => t.language.toLowerCase().contains('eng') || (t.title?.toLowerCase().contains('eng') ?? false),
            orElse: () => meta.availableTracks.first
          );
          _batchVideos.add(meta);
        }
      }
      _updateStatus('Encontrados ${_batchVideos.length} vídeos com legendas.');
    } catch (e) {
      _updateStatus('Erro ao ler pasta: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- TRADUÇÃO EM LOTE COMPLETO ---
  Future<void> _processBatchFull() async {
    if (_apiKey.isEmpty) { _showSettings(); return; }
    String? outDir = await _resolveOutputDir();
    if (outDir == null) return;

    setState(() => _isLoading = true);
    int sucesso = 0;

    for (int i = 0; i < _batchVideos.length; i++) {
      var video = _batchVideos[i];
      // Regra de Ouro: Pula se não tiver trilha ou se JÁ ESTIVER TRADUZIDO
      if (video.selectedTrack == null || video.isTranslated) continue; 

      setState(() => _status = 'Traduzindo Automático ${i + 1}/${_batchVideos.length}:\n${video.fileName}');

      try {
        final dialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, video.selectedTrack!.index);
        final translatedJsonStr = await GeminiService.translateSubtitles(dialogues: dialogues, apiKey: _apiKey);
        
        await _saveAndGenerate(video, translatedJsonStr, outDir);
        sucesso++;
      } catch (e) {
        print("Erro no vídeo ${video.fileName}: $e");
      }
    }

    setState(() {
      _isLoading = false;
      _status = 'Lote concluído! $sucesso processados agora.';
    });

    if (await canLaunchUrl(Uri.directory(outDir))) await launchUrl(Uri.directory(outDir));
  }

  // --- DIÁLOGOS ---
  void _showPasteTranslatedJsonDialog(VideoMetadata video) {
    _pasteController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Colar Tradução - ${video.fileName}'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(controller: _pasteController, maxLines: 8, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Cole o JSON...')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (_pasteController.text.isNotEmpty) {
                try {
                  final cleaned = JsonUtils.cleanJson(_pasteController.text);
                  jsonDecode(cleaned); // Validação de segurança
                  Navigator.pop(context);
                  
                  String? outDir = await _resolveOutputDir();
                  if (outDir != null) {
                    setState(() => _isLoading = true);
                    await _saveAndGenerate(video, cleaned, outDir);
                    setState(() { _isLoading = false; _status = 'Sucesso manual: ${video.fileName}'; });
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('JSON inválido: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Gerar MKV'),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuração API'),
        content: TextField(controller: _apiKeyController, decoration: const InputDecoration(labelText: 'Gemini API Key'), obscureText: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
          ElevatedButton(onPressed: () { setState(() => _apiKey = _apiKeyController.text); Navigator.pop(context); }, child: const Text('Salvar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SubsTract Pro'),
        actions: [IconButton(icon: const Icon(Icons.vpn_key), onPressed: _showSettings)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.video_file), label: const Text('Selecionar 1 Vídeo'), onPressed: _isLoading ? null : _pickVideo)),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.folder), label: const Text('Selecionar Pasta (Lote)'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]), onPressed: _isLoading ? null : _pickFolderAndAnalyze)),
              ],
            ),
            
            // --- UI MODO LOTE ---
            if (_isBatchMode && _batchVideos.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Vídeos na Pasta:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
              const SizedBox(height: 10),
              Container(
                height: 400,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)),
                child: ListView.builder(
                  itemCount: _batchVideos.length,
                  itemBuilder: (context, index) {
                    final video = _batchVideos[index];
                    return Card(
                      // Fica verde claro se já estiver concluído!
                      color: video.isTranslated ? Colors.green.withOpacity(0.15) : null,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(video.fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                                if (video.isTranslated) const Icon(Icons.check_circle, color: Colors.green),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButton<SubtitleTrack>(
                              isExpanded: true,
                              value: video.selectedTrack,
                              items: video.availableTracks.map((t) => DropdownMenuItem(value: t, child: Text(t.toString()))).toList(),
                              onChanged: (v) => setState(() => video.selectedTrack = v),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: TextFormField(initialValue: video.title, decoration: const InputDecoration(labelText: 'Título', isDense: true), onChanged: (v) => video.title = v)),
                                const SizedBox(width: 10),
                                Expanded(child: TextFormField(initialValue: video.episode, decoration: const InputDecoration(labelText: 'Episódio', isDense: true), onChanged: (v) => video.episode = v)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Botões individuais de tradução
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(icon: const Icon(Icons.auto_fix_high), color: Colors.indigoAccent, tooltip: 'Traduzir este via API', onPressed: video.isTranslated ? null : () => _processVideoAPI(video)),
                                IconButton(icon: const Icon(Icons.copy_all), tooltip: 'Copiar Prompt', onPressed: video.isTranslated ? null : () => _copyPromptForVideo(video)),
                                IconButton(icon: const Icon(Icons.folder_open), tooltip: 'Salvar JSON e Traduzir', onPressed: video.isTranslated ? null : () => _saveOriginalJsonForVideo(video)),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.batch_prediction), 
                label: const Text('Traduzir Lote Completo (Pula os concluídos)'), 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.all(16)), 
                onPressed: _isLoading ? null : _processBatchFull
              ),
            ],

            // --- UI MODO ÚNICO ---
            if (!_isBatchMode && _currentMetadata != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Text('Arquivo: ${_currentMetadata!.fileName}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (_currentMetadata!.isTranslated) const Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<SubtitleTrack>(
                value: _selectedTrack,
                items: _availableTracks.map((t) => DropdownMenuItem(value: t, child: Text(t.toString()))).toList(),
                onChanged: (v) => setState(() => _selectedTrack = v),
                decoration: const InputDecoration(labelText: 'Trilha de Legenda'),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(flex: 3, child: TextField(controller: _titleController, onChanged: (v) => _currentMetadata!.title = v, decoration: const InputDecoration(labelText: 'Título'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _episodeController, onChanged: (v) => _currentMetadata!.episode = v, decoration: const InputDecoration(labelText: 'Ep'))),
                ],
              ),
              const SizedBox(height: 30),
              const Text('AÇÕES INDIVIDUAIS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              ElevatedButton.icon(icon: const Icon(Icons.auto_fix_high), label: const Text('Traduzir via API'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo), onPressed: _isLoading || _currentMetadata!.isTranslated ? null : () => _processVideoAPI(_currentMetadata!)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy_all), label: const Text('Copiar Prompt'), onPressed: _isLoading || _currentMetadata!.isTranslated ? null : () => _copyPromptForVideo(_currentMetadata!))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.folder_open), label: const Text('Salvar e Traduzir'), onPressed: _isLoading || _currentMetadata!.isTranslated ? null : () => _saveOriginalJsonForVideo(_currentMetadata!))),
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