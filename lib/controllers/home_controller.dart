import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/video_metadata.dart';
import '../services/ffmpeg_service.dart';
import '../services/gemini_service.dart';
import '../utils/json_utils.dart';

class HomeController extends ChangeNotifier {
  String status = 'Selecione um vídeo ou uma pasta para começar.';
  bool isLoading = false;
  
  // Controle de Estado
  VideoMetadata? currentMetadata;
  List<SubtitleTrack> availableTracks = [];
  SubtitleTrack? selectedTrack;
  
  bool isBatchMode = false;
  List<VideoMetadata> batchVideos = [];
  String? batchOutputDir;

  // Listas visuais
  List<String> extractedDialogues = [];
  List<String> translatedDialogues = [];
  
  // Controle do Modo de Edição
  bool isEditingRawTranslation = false; 
  int? editingLineIndex; 
  
  // NOVO: Prompt customizável
  String customPrompt = "Atue como tradutor de animes. Traduza este array JSON para PT-BR mantendo as tags. Mantenha o mesmo número de falas do json resposta.traduza somente as falas em inglês, mantenha as que estiverem em japonês romaji da forma como estão.MUITO IMPORTANTE: 1. Substitua aspas duplas internas por aspas simples (').2. Adicione uma barra extra nas tags de estilo. Ex: {\pos(x,y)} vira {\\pos(x,y)}.Responda APENAS o JSON:";
  
  // Controladores de Texto
  final translationController = TextEditingController(); 
  final inlineEditController = TextEditingController(); 
  final titleController = TextEditingController();
  final episodeController = TextEditingController();

  HomeController() {
    _initChecks();
  }

  void updateStatus(String msg) {
    status = msg;
    notifyListeners();
  }

  void setLoading(bool val) {
    isLoading = val;
    notifyListeners();
  }

  Future<void> _initChecks() async {
    bool hasFfmpeg = await FFmpegService.isFFmpegInstalled();
    if (!hasFfmpeg) updateStatus('Erro: FFmpeg não detectado no sistema.');
  }

  Future<String?> resolveOutputDir() async {
    if (isBatchMode) {
      if (batchOutputDir != null) return batchOutputDir;
      batchOutputDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Onde deseja salvar os arquivos deste lote?');
      return batchOutputDir;
    } else {
      return await FilePicker.platform.getDirectoryPath(dialogTitle: 'Onde salvar o vídeo traduzido?');
    }
  }

  Future<void> selectVideo(VideoMetadata video) async {
    currentMetadata = video;
    selectedTrack = video.selectedTrack;
    availableTracks = video.availableTracks;
    titleController.text = video.title;
    episodeController.text = video.episode;
    extractedDialogues.clear();
    translatedDialogues.clear();
    isEditingRawTranslation = false; 
    editingLineIndex = null;
    setLoading(true);

    try {
      if (selectedTrack != null) {
        extractedDialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, selectedTrack!.index);
      }
    } catch (e) {
      updateStatus('Erro ao extrair legendas: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> saveAndGenerate(VideoMetadata video, String jsonStr, String outDir) async {
    String epStr = video.episode.isNotEmpty ? '_E${video.episode}' : '';
    String jsonSavePath = p.join(outDir, '${video.title}$epStr\_PTBR.json');
    await File(jsonSavePath).writeAsString(jsonStr);
    
    await FFmpegService.generateFinalVideo(
      originalVideoPath: video.filePath,
      translatedJsonStr: jsonStr,
      outputDirectory: outDir,
      titleStr: video.title,
      epStr: video.episode,
      onProgress: updateStatus,
    );
    
    video.isTranslated = true;
    notifyListeners();
  }

  Future<void> processVideoAPI(VideoMetadata video, String apiKey) async {
    setLoading(true);
    updateStatus('Traduzindo ${video.fileName}...');
    try {
      final dialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, video.selectedTrack!.index);
      final translatedJsonStr = await GeminiService.translateSubtitles(dialogues: dialogues, apiKey: apiKey);
      
      final translatedList = jsonDecode(translatedJsonStr) as List;
      translatedDialogues = translatedList.map((e) => e.toString()).toList();
      translationController.text = translatedJsonStr; 
      updateStatus('Tradução recebida! Revise e clique em "Gerar MKV".'); 
    } catch (e) {
      updateStatus('Erro: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> generateManualMKV(VideoMetadata video) async {
    if (translatedDialogues.isEmpty) {
      updateStatus('Nenhuma tradução para gerar.');
      return;
    }
    String? outDir = await resolveOutputDir();
    if (outDir == null) return;

    setLoading(true);
    updateStatus('Gerando vídeo final...');
    try {
      String jsonStr = jsonEncode(translatedDialogues);
      await saveAndGenerate(video, jsonStr, outDir);
      updateStatus('Vídeo salvo com sucesso!');
    } catch (e) {
      updateStatus('Erro ao gerar: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> processBatchFull(String apiKey) async {
    String? outDir = await resolveOutputDir();
    if (outDir == null) return;

    setLoading(true);
    int sucesso = 0;

    for (int i = 0; i < batchVideos.length; i++) {
      var video = batchVideos[i];
      if (video.selectedTrack == null || video.isTranslated) continue; 

      updateStatus('Processando Lote ${i + 1}/${batchVideos.length}:\n${video.fileName}');
      currentMetadata = video;
      notifyListeners();

      try {
        final dialogues = await FFmpegService.extractSubtitlesToMemory(video.filePath, video.selectedTrack!.index);
        extractedDialogues = dialogues;
        notifyListeners();

        final translatedJsonStr = await GeminiService.translateSubtitles(dialogues: dialogues, apiKey: apiKey);
        final translatedList = jsonDecode(translatedJsonStr) as List;
        
        translatedDialogues = translatedList.map((e) => e.toString()).toList();
        translationController.text = translatedJsonStr;
        notifyListeners();

        await saveAndGenerate(video, translatedJsonStr, outDir);
        sucesso++;
      } catch (e) {
        print("Erro no vídeo ${video.fileName}: $e");
      }
    }

    updateStatus('Lote concluído! $sucesso processados.');
    setLoading(false);

    if (await canLaunchUrl(Uri.directory(outDir))) await launchUrl(Uri.directory(outDir));
  }

  Future<void> pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      final path = result.files.single.path!;
      final meta = VideoMetadata.fromPath(path);
      
      isBatchMode = false;
      batchVideos.clear();
      setLoading(true);
      
      try {
        meta.availableTracks = await FFmpegService.analyzeTracks(path);
        if (meta.availableTracks.isNotEmpty) {
          meta.selectedTrack = meta.availableTracks.firstWhere(
            (t) => t.language.toLowerCase().contains('eng') || (t.title?.toLowerCase().contains('eng') ?? false),
            orElse: () => meta.availableTracks.first
          );
        }
        await selectVideo(meta);
        updateStatus('Vídeo carregado.');
      } catch (e) {
        updateStatus('Erro: $e');
      } finally {
        setLoading(false);
      }
    }
  }

  Future<void> pickFolderAndAnalyze() async {
    String? dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;

    isBatchMode = true;
    batchOutputDir = null;
    batchVideos.clear();
    extractedDialogues.clear();
    translatedDialogues.clear();
    currentMetadata = null;
    isEditingRawTranslation = false;
    editingLineIndex = null;
    setLoading(true);
    updateStatus('Varrendo pasta...');

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
          batchVideos.add(meta);
        }
      }
      
      if (batchVideos.isNotEmpty) {
        await selectVideo(batchVideos.first);
      }
      updateStatus('Encontrados ${batchVideos.length} vídeos com legendas.');
    } catch (e) {
      updateStatus('Erro ao ler pasta: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> copyPromptForVideo() async {
    // Agora ele une o prompt customizado com o JSON extraído
    final finalPrompt = "$customPrompt\n\n${jsonEncode(extractedDialogues)}";
        
    await Clipboard.setData(ClipboardData(text: finalPrompt));
    updateStatus('Prompt copiado! Cole o resultado no painel de Tradução.');
    translationController.clear();
    isEditingRawTranslation = true; 
    notifyListeners();
  }

  Future<void> saveOriginalJsonForVideo() async {
    if (currentMetadata == null) return;
    String? path;
    if (isBatchMode) {
      String? outDir = await resolveOutputDir();
      if (outDir == null) return;
      String epStr = currentMetadata!.episode.isNotEmpty ? '_E${currentMetadata!.episode}' : '';
      path = p.join(outDir, '${currentMetadata!.title}$epStr\_original.json');
      await File(path).writeAsString(jsonEncode(extractedDialogues));
    } else {
      path = await FilePicker.platform.saveFile(
        fileName: '${currentMetadata!.title}_E${currentMetadata!.episode}_original.json',
        bytes: utf8.encode(jsonEncode(extractedDialogues)),
      );
    }

    if (path != null) {
      final folder = p.dirname(path);
      if (await canLaunchUrl(Uri.directory(folder))) await launchUrl(Uri.directory(folder));
      updateStatus('JSON Salvo! Cole o resultado no painel de Tradução.');
      translationController.clear();
      isEditingRawTranslation = true;
      notifyListeners();
    }
  }

  void validateTranslationJson() {
    try {
      final cleaned = JsonUtils.cleanJson(translationController.text);
      final translatedList = jsonDecode(cleaned) as List;
      translatedDialogues = translatedList.map((e) => e.toString()).toList();
      isEditingRawTranslation = false; 
      editingLineIndex = null;
      updateStatus('Tradução aplicada! Clique em uma linha para editar ou gere o MKV.');
    } catch (e) {
      throw Exception(e); 
    }
  }

  void toggleRawEditMode() {
    if (!isEditingRawTranslation && translatedDialogues.isNotEmpty) {
      translationController.text = jsonEncode(translatedDialogues);
    }
    isEditingRawTranslation = !isEditingRawTranslation;
    editingLineIndex = null;
    notifyListeners();
  }

  void setEditingLine(int? index, [String? text]) {
    editingLineIndex = index;
    if (text != null) inlineEditController.text = text;
    notifyListeners();
  }

  void updateTranslatedLine(int index, String val) {
    if (index < translatedDialogues.length) {
      translatedDialogues[index] = val;
    }
    editingLineIndex = null;
    notifyListeners();
  }

  void changeTrack(SubtitleTrack track) {
    if (currentMetadata != null) {
      currentMetadata!.selectedTrack = track;
      selectVideo(currentMetadata!);
    }
  }

  @override
  void dispose() {
    translationController.dispose();
    inlineEditController.dispose();
    titleController.dispose();
    episodeController.dispose();
    super.dispose();
  }
}