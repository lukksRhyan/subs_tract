import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/video_metadata.dart';
import '../services/ffmpeg_service.dart';
import '../services/gemini_service.dart';
import '../utils/json_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = 'Selecione um vídeo ou uma pasta para começar.';
  bool _isLoading = false;
  String _apiKey = '';
  
  // Controle de Estado
  VideoMetadata? _currentMetadata;
  List<SubtitleTrack> _availableTracks = [];
  SubtitleTrack? _selectedTrack;
  
  bool _isBatchMode = false;
  List<VideoMetadata> _batchVideos = [];
  String? _batchOutputDir;

  // Listas visuais
  List<String> _extractedDialogues = [];
  List<String> _translatedDialogues = [];
  
  // Controle do Modo de Edição
  bool _isEditingRawTranslation = false; 
  int? _editingLineIndex; 
  
  final _translationController = TextEditingController(); 
  final _inlineEditController = TextEditingController(); 

  final _titleController = TextEditingController();
  final _episodeController = TextEditingController();
  final _apiKeyController = TextEditingController();

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
    _translationController.dispose();
    _inlineEditController.dispose();
    super.dispose();
  }

  Future<void> _initChecks() async {
    bool hasFfmpeg = await FFmpegService.isFFmpegInstalled();
    if (!hasFfmpeg) setState(() => _status = 'Erro: FFmpeg não detectado no sistema.');
  }

  void _updateStatus(String msg) {
    if (mounted) setState(() => _status = msg);
  }

  Future<String?> _resolveOutputDir() async {
    if (_isBatchMode) {
      if (_batchOutputDir != null) return _batchOutputDir;
      _batchOutputDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Onde deseja salvar os arquivos deste lote?');
      return _batchOutputDir;
    } else {
      return await FilePicker.platform.getDirectoryPath(dialogTitle: 'Onde salvar o vídeo traduzido?');
    }
  }

  // --- CONTROLE DE UI ---
  Future<void> _selectVideo(VideoMetadata video) async {
    setState(() {
      _currentMetadata = video;
      _selectedTrack = video.selectedTrack;
      _availableTracks = video.availableTracks;
      _titleController.text = video.title;
      _episodeController.text = video.episode;
      _extractedDialogues.clear();
      _translatedDialogues.clear();
      _isEditingRawTranslation = false; 
      _editingLineIndex = null;
      _isLoading = true;
    });

    try {
      if (_selectedTrack != null) {
        _extractedDialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, _selectedTrack!.index);
      }
    } catch (e) {
      _updateStatus('Erro ao extrair legendas: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- NÚCLEO DE TRADUÇÃO E GERAÇÃO ---
  Future<void> _saveAndGenerate(VideoMetadata video, String jsonStr, String outDir) async {
    String epStr = video.episode.isNotEmpty ? '_E${video.episode}' : '';
    String jsonSavePath = p.join(outDir, '${video.title}$epStr\_PTBR.json');
    await File(jsonSavePath).writeAsString(jsonStr);
    
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

    setState(() { _isLoading = true; _status = 'Traduzindo ${video.fileName}...'; });
    try {
      final dialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, video.selectedTrack!.index);
      final translatedJsonStr = await GeminiService.translateSubtitles(dialogues: dialogues, apiKey: _apiKey);
      
      final translatedList = jsonDecode(translatedJsonStr) as List;
      setState(() {
        _translatedDialogues = translatedList.map((e) => e.toString()).toList();
        _translationController.text = translatedJsonStr; 
        _isLoading = false; 
        _status = 'Tradução recebida! Revise e clique em "Gerar MKV".'; 
      });
    } catch (e) {
      setState(() { _isLoading = false; _status = 'Erro: $e'; });
    }
  }

  Future<void> _generateManualMKV(VideoMetadata video) async {
    if (_translatedDialogues.isEmpty) {
      _updateStatus('Nenhuma tradução para gerar.');
      return;
    }
    String? outDir = await _resolveOutputDir();
    if (outDir == null) return;

    setState(() { _isLoading = true; _status = 'Gerando vídeo final...'; });
    try {
      String jsonStr = jsonEncode(_translatedDialogues);
      await _saveAndGenerate(video, jsonStr, outDir);
      setState(() { _isLoading = false; _status = 'Vídeo salvo com sucesso!'; });
    } catch (e) {
      setState(() { _isLoading = false; _status = 'Erro ao gerar: $e'; });
    }
  }

  Future<void> _processBatchFull() async {
    if (_apiKey.isEmpty) { _showSettings(); return; }
    String? outDir = await _resolveOutputDir();
    if (outDir == null) return;

    setState(() => _isLoading = true);
    int sucesso = 0;

    for (int i = 0; i < _batchVideos.length; i++) {
      var video = _batchVideos[i];
      if (video.selectedTrack == null || video.isTranslated) continue; 

      setState(() {
        _status = 'Processando Lote ${i + 1}/${_batchVideos.length}:\n${video.fileName}';
        _currentMetadata = video;
      });

      try {
        final dialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, video.selectedTrack!.index);
        setState(() => _extractedDialogues = dialogues);

        final translatedJsonStr = await GeminiService.translateSubtitles(dialogues: dialogues, apiKey: _apiKey);
        final translatedList = jsonDecode(translatedJsonStr) as List;
        
        setState(() {
          _translatedDialogues = translatedList.map((e) => e.toString()).toList();
          _translationController.text = translatedJsonStr;
        });

        await _saveAndGenerate(video, translatedJsonStr, outDir);
        sucesso++;
      } catch (e) {
        print("Erro no vídeo ${video.fileName}: $e");
      }
    }

    setState(() {
      _isLoading = false;
      _status = 'Lote concluído! $sucesso processados.';
    });

    if (await canLaunchUrl(Uri.directory(outDir))) await launchUrl(Uri.directory(outDir));
  }

  // --- SELEÇÃO DE ARQUIVOS E PASTAS ---
  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      final path = result.files.single.path!;
      final meta = VideoMetadata.fromPath(path);
      
      setState(() {
        _isBatchMode = false;
        _batchVideos.clear();
        _isLoading = true;
      });
      
      try {
        meta.availableTracks = await FFmpegService.analyzeTracks(path);
        if (meta.availableTracks.isNotEmpty) {
          meta.selectedTrack = meta.availableTracks.firstWhere(
            (t) => t.language.toLowerCase().contains('eng') || (t.title?.toLowerCase().contains('eng') ?? false),
            orElse: () => meta.availableTracks.first
          );
        }
        await _selectVideo(meta);
        _updateStatus('Vídeo carregado.');
      } catch (e) {
        _updateStatus('Erro: $e');
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
      _batchOutputDir = null;
      _batchVideos = [];
      _extractedDialogues.clear();
      _translatedDialogues.clear();
      _currentMetadata = null;
      _isEditingRawTranslation = false;
      _editingLineIndex = null;
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
      
      if (_batchVideos.isNotEmpty) {
        await _selectVideo(_batchVideos.first);
      }
      _updateStatus('Encontrados ${_batchVideos.length} vídeos com legendas.');
    } catch (e) {
      _updateStatus('Erro ao ler pasta: $e');
      setState(() => _isLoading = false);
    }
  }

  // --- MÉTODOS MANUAIS E VALIDAÇÃO ---
  void _copyPromptForVideo() async {
    final prompt = "Atue como tradutor de animes. Traduza este array JSON para PT-BR mantendo as tags. "
        "MUITO IMPORTANTE: 1. Substitua aspas duplas internas por aspas simples ('). "
        "2. Adicione uma barra extra nas tags de estilo. Ex: {\\pos(x,y)} vira {\\\\pos(x,y)}. "
        "Responda APENAS o JSON:\n\n${jsonEncode(_extractedDialogues)}";
        
    await Clipboard.setData(ClipboardData(text: prompt));
    setState(() {
      _status = 'Prompt copiado! Cole o resultado no painel de Tradução.';
      _translationController.clear();
      _isEditingRawTranslation = true; 
    });
  }

  Future<void> _saveOriginalJsonForVideo() async {
    String? path;
    if (_isBatchMode) {
      String? outDir = await _resolveOutputDir();
      if (outDir == null) return;
      String epStr = _currentMetadata!.episode.isNotEmpty ? '_E${_currentMetadata!.episode}' : '';
      path = p.join(outDir, '${_currentMetadata!.title}$epStr\_original.json');
      await File(path).writeAsString(jsonEncode(_extractedDialogues));
    } else {
      path = await FilePicker.platform.saveFile(
        fileName: '${_currentMetadata!.title}_E${_currentMetadata!.episode}_original.json',
        bytes: utf8.encode(jsonEncode(_extractedDialogues)),
      );
    }

    if (path != null) {
      final folder = p.dirname(path);
      if (await canLaunchUrl(Uri.directory(folder))) await launchUrl(Uri.directory(folder));
      setState(() {
        _status = 'JSON Salvo! Cole o resultado no painel de Tradução.';
        _translationController.clear();
        _isEditingRawTranslation = true;
      });
    }
  }

  void _validateTranslationJson() {
    try {
      final cleaned = JsonUtils.cleanJson(_translationController.text);
      final translatedList = jsonDecode(cleaned) as List;
      setState(() {
        _translatedDialogues = translatedList.map((e) => e.toString()).toList();
        _isEditingRawTranslation = false; 
        _editingLineIndex = null;
        _status = 'Tradução aplicada! Clique em uma linha para editar ou gere o MKV.';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('JSON inválido: $e'), backgroundColor: Colors.red));
    }
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

  // --- WIDGETS DE CONSTRUÇÃO ---

  Widget _buildSectionContainer(String title, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: const BoxDecoration(
              color: Colors.black26,
              border: Border(bottom: BorderSide(color: Colors.white24)),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8))
            ),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.all(8.0), child: child)),
        ],
      ),
    );
  }

  // Lista simples de extração para usar quando o painel direito estiver em modo de edição RAW
  Widget _buildSimpleSubtitleList(List<String> items, String emptyMessage) {
    if (items.isEmpty) return Center(child: Text(emptyMessage, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center));
    
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          child: Text(items[index], style: const TextStyle(fontSize: 13, height: 1.4)),
        );
      },
    );
  }

  // O Item Traduzido (Normal ou Modo de Edição em Linha)
  Widget _buildTranslatedItem(int index, String trans) {
    if (_translatedDialogues.isEmpty) {
      if (index == 0) {
         return const Padding(
           padding: EdgeInsets.all(8.0),
           child: Text('Aguardando tradução...', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
         );
      }
      return const SizedBox();
    }

    if (_editingLineIndex == index) {
      return Container(
        color: Colors.white.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _inlineEditController,
                autofocus: true,
                maxLines: null,
                style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.amberAccent),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder()),
                onSubmitted: (val) {
                  setState(() {
                    if (index < _translatedDialogues.length) _translatedDialogues[index] = val;
                    _editingLineIndex = null;
                  });
                },
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green, size: 20),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  tooltip: 'Salvar',
                  onPressed: () {
                    setState(() {
                      if (index < _translatedDialogues.length) _translatedDialogues[index] = _inlineEditController.text;
                      _editingLineIndex = null;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  tooltip: 'Cancelar',
                  onPressed: () => setState(() => _editingLineIndex = null),
                ),
              ],
            )
          ],
        ),
      );
    }

    return InkWell(
      onTap: () {
        setState(() {
          _editingLineIndex = index;
          _inlineEditController.text = trans;
        });
      },
      hoverColor: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(trans, style: const TextStyle(fontSize: 13, height: 1.4))),
            const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(Icons.edit, size: 14, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }

  // A Mágica: Lista Sincronizada onde cada linha é um Row com Original e Tradução
  Widget _buildSynchronizedList() {
    if (_extractedDialogues.isEmpty && _translatedDialogues.isEmpty) {
      return const Center(child: Text('Nenhuma legenda carregada.', style: TextStyle(color: Colors.grey)));
    }

    int itemCount = math.max(_extractedDialogues.length, _translatedDialogues.length);

    return ListView.separated(
      itemCount: itemCount,
      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
      itemBuilder: (context, index) {
        final orig = index < _extractedDialogues.length ? _extractedDialogues[index] : '';
        final trans = index < _translatedDialogues.length ? _translatedDialogues[index] : '';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coluna Original
            Expanded(
              child: Container(
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24))),
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                child: Text(orig, style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
            ),
            // Coluna Tradução
            Expanded(
              child: Padding(
                padding: EdgeInsets.zero,
                child: _buildTranslatedItem(index, trans),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('SubsTract Pro', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
        actions: [
          Center(child: Padding(padding: const EdgeInsets.only(right: 16.0), child: Text(_status, style: TextStyle(color: Colors.tealAccent[100], fontSize: 12, fontStyle: FontStyle.italic)))),
          if (_isLoading) const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
          IconButton(icon: const Icon(Icons.vpn_key), tooltip: 'Configurações API', onPressed: _showSettings),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // ================== LADO ESQUERDO (Painel Unificado de Legendas) ==================
            Expanded(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    // CABEÇALHO DUPLO
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: const BoxDecoration(
                              color: Colors.black26,
                              border: Border(bottom: BorderSide(color: Colors.white24), right: BorderSide(color: Colors.white24)),
                              borderRadius: BorderRadius.only(topLeft: Radius.circular(8)),
                            ),
                            child: const Text('Legendas Originais', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                            decoration: const BoxDecoration(
                              color: Colors.black26,
                              border: Border(bottom: BorderSide(color: Colors.white24)),
                              borderRadius: BorderRadius.only(topRight: Radius.circular(8)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(child: Text('Tradução', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)),
                                if (_currentMetadata != null)
                                  IconButton(
                                    icon: Icon(_isEditingRawTranslation ? Icons.close : Icons.paste, size: 20, color: _isEditingRawTranslation ? Colors.redAccent : Colors.white),
                                    tooltip: _isEditingRawTranslation ? 'Cancelar Colagem' : 'Colar JSON Completo',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      setState(() {
                                        if (!_isEditingRawTranslation && _translatedDialogues.isNotEmpty) {
                                          _translationController.text = jsonEncode(_translatedDialogues);
                                        }
                                        _isEditingRawTranslation = !_isEditingRawTranslation;
                                        _editingLineIndex = null;
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    // CORPO (Lista Sincronizada ou Editor Raw)
                    Expanded(
                      child: _isEditingRawTranslation
                        ? Row(
                            children: [
                              // Se estiver editando RAW, mostra apenas a lista original na esquerda
                              Expanded(child: _buildSimpleSubtitleList(_extractedDialogues, 'Nenhuma legenda extraída.')),
                              const VerticalDivider(width: 1, color: Colors.white24),
                              // E o campo grande na direita
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _translationController,
                                          maxLines: null,
                                          expands: true,
                                          style: const TextStyle(fontSize: 13, fontFamily: 'Courier', color: Colors.amberAccent),
                                          decoration: const InputDecoration(
                                            hintText: 'Cole o array JSON completo aqui...',
                                            border: OutlineInputBorder(),
                                            filled: true,
                                            fillColor: Colors.black12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.check),
                                          label: const Text('Validar e Aplicar Tradução'),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                          onPressed: _validateTranslationJson,
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : _buildSynchronizedList(), // A Lista Mágica!
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // ================== LADO DIREITO (Controles) ==================
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildSectionContainer('Informações do vídeo', _currentMetadata == null 
                            ? const Center(child: Text('Nenhum vídeo focado.', style: TextStyle(color: Colors.grey)))
                            : SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Arquivo: ${_currentMetadata!.fileName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<SubtitleTrack>(
                                    isExpanded: true,
                                    value: _selectedTrack,
                                    items: _availableTracks.map((t) => DropdownMenuItem(value: t, child: Text(t.toString(), style: const TextStyle(fontSize: 13)))).toList(),
                                    onChanged: (v) async {
                                      _currentMetadata!.selectedTrack = v;
                                      await _selectVideo(_currentMetadata!);
                                    },
                                    decoration: const InputDecoration(labelText: 'Trilha Fonte', border: OutlineInputBorder(), isDense: true),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _titleController,
                                    onChanged: (v) => _currentMetadata!.title = v,
                                    decoration: const InputDecoration(labelText: 'Título da Série/Vídeo', border: OutlineInputBorder(), isDense: true),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _episodeController,
                                    onChanged: (v) => _currentMetadata!.episode = v,
                                    decoration: const InputDecoration(labelText: 'Número do Episódio', border: OutlineInputBorder(), isDense: true),
                                  ),
                                  const SizedBox(height: 20),
                                  if (_currentMetadata!.isTranslated)
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      color: Colors.green.withOpacity(0.2),
                                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('Tradução Concluída', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
                                    )
                                ],
                              ),
                            )
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSectionContainer('Outros vídeos da pasta', !_isBatchMode || _batchVideos.isEmpty
                            ? const Center(child: Text('Modo Lote inativo.', style: TextStyle(color: Colors.grey)))
                            : ListView.builder(
                                itemCount: _batchVideos.length,
                                itemBuilder: (context, index) {
                                  final video = _batchVideos[index];
                                  final isSelected = _currentMetadata?.filePath == video.filePath;
                                  return ListTile(
                                    dense: true,
                                    selected: isSelected,
                                    selectedTileColor: Colors.blueAccent.withOpacity(0.2),
                                    title: Text(video.fileName, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    trailing: video.isTranslated ? const Icon(Icons.check, color: Colors.green, size: 18) : null,
                                    onTap: () => _selectVideo(video),
                                  );
                                },
                              )
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 1,
                    child: _buildSectionContainer('Ações', Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Row(
                          children: [
                            Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.video_file), label: const Text('Selecionar 1 Vídeo'), onPressed: _isLoading ? null : _pickVideo)),
                            const SizedBox(width: 10),
                            Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.folder), label: const Text('Selecionar Pasta (Lote)'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]), onPressed: _isLoading ? null : _pickFolderAndAnalyze)),
                          ],
                        ),
                        const Divider(color: Colors.white24),
                        Row(
                          children: [
                            Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.auto_fix_high), label: const Text('Traduzir (API)'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent), onPressed: _isLoading || _currentMetadata == null || _currentMetadata!.isTranslated ? null : () => _processVideoAPI(_currentMetadata!))),
                            const SizedBox(width: 10),
                            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy), label: const Text('Copiar Prompt'), onPressed: _isLoading || _currentMetadata == null || _currentMetadata!.isTranslated ? null : _copyPromptForVideo)),
                            const SizedBox(width: 10),
                            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.save), label: const Text('Salvar .json'), onPressed: _isLoading || _currentMetadata == null || _currentMetadata!.isTranslated ? null : _saveOriginalJsonForVideo)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.movie_creation), 
                                label: const Text('GERAR MKV (VÍDEO ATUAL)'), 
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                                onPressed: _isLoading || _translatedDialogues.isEmpty || (_currentMetadata?.isTranslated ?? true) ? null : () => _generateManualMKV(_currentMetadata!)
                              ),
                            ),
                          ],
                        ),
                        if (_isBatchMode) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.batch_prediction), 
                              label: const Text('PROCESSAR LOTE COMPLETO (Automático)'), 
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
                              onPressed: _isLoading ? null : _processBatchFull
                            ),
                          )
                        ]
                      ],
                    )),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}