import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../models/video_metadata.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Instância do nosso controlador (O "Cérebro")
  final HomeController _controller = HomeController();
  
  // Variáveis que pertencem estritamente à UI
  String _apiKey = '';
  final _apiKeyController = TextEditingController();

  @override
  void dispose() {
    _apiKeyController.dispose();
    _controller.dispose();
    super.dispose();
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

  void _handleAPIProcess(VideoMetadata video) {
    if (_apiKey.isEmpty) {
      _showSettings();
    } else {
      _controller.processVideoAPI(video, _apiKey);
    }
  }

  void _handleBatchFullProcess() {
    if (_apiKey.isEmpty) {
      _showSettings();
    } else {
      _controller.processBatchFull(_apiKey);
    }
  }

  void _handleJsonValidation() {
    try {
      _controller.validateTranslationJson();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('JSON inválido: $e'), backgroundColor: Colors.red));
    }
  }

  // --- WIDGETS AUXILIARES DE UI ---
  Widget _buildSectionContainer(String title, Widget child) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: const BoxDecoration(color: Colors.black26, border: Border(bottom: BorderSide(color: Colors.white24)), borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8))),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.all(8.0), child: child)),
        ],
      ),
    );
  }

  Widget _buildSimpleSubtitleList(List<String> items, String emptyMessage) {
    if (items.isEmpty) return Center(child: Text(emptyMessage, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center));
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
      itemBuilder: (context, index) => Padding(padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0), child: Text(items[index], style: const TextStyle(fontSize: 13, height: 1.4))),
    );
  }

  Widget _buildTranslatedItem(int index, String trans) {
    if (_controller.translatedDialogues.isEmpty) {
      if (index == 0) return const Padding(padding: EdgeInsets.all(8.0), child: Text('Aguardando tradução...', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)));
      return const SizedBox();
    }

    if (_controller.editingLineIndex == index) {
      return Container(
        color: Colors.white.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller.inlineEditController,
                autofocus: true,
                maxLines: null,
                style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.amberAccent),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder()),
                onSubmitted: (val) => _controller.updateTranslatedLine(index, val),
              ),
            ),
            Column(
              children: [
                IconButton(icon: const Icon(Icons.check, color: Colors.green, size: 20), constraints: const BoxConstraints(), padding: const EdgeInsets.all(4), tooltip: 'Salvar', onPressed: () => _controller.updateTranslatedLine(index, _controller.inlineEditController.text)),
                IconButton(icon: const Icon(Icons.close, color: Colors.redAccent, size: 20), constraints: const BoxConstraints(), padding: const EdgeInsets.all(4), tooltip: 'Cancelar', onPressed: () => _controller.setEditingLine(null)),
              ],
            )
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _controller.setEditingLine(index, trans),
      hoverColor: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(trans, style: const TextStyle(fontSize: 13, height: 1.4))),
            const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.edit, size: 14, color: Colors.white24)),
          ],
        ),
      ),
    );
  }

  Widget _buildSynchronizedList() {
    if (_controller.extractedDialogues.isEmpty && _controller.translatedDialogues.isEmpty) {
      return const Center(child: Text('Nenhuma legenda carregada.', style: TextStyle(color: Colors.grey)));
    }
    int itemCount = math.max(_controller.extractedDialogues.length, _controller.translatedDialogues.length);
    return ListView.separated(
      itemCount: itemCount,
      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
      itemBuilder: (context, index) {
        final orig = index < _controller.extractedDialogues.length ? _controller.extractedDialogues[index] : '';
        final trans = index < _controller.translatedDialogues.length ? _controller.translatedDialogues[index] : '';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Container(decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24))), padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0), child: Text(orig, style: const TextStyle(fontSize: 13, height: 1.4)))),
            Expanded(child: Padding(padding: EdgeInsets.zero, child: _buildTranslatedItem(index, trans))),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // O ListenableBuilder escuta o Controller e reconstrói a tela quando necessário
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            title: const Text('SubsTract Pro', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF1F1F1F),
            elevation: 0,
            actions: [
              Center(child: Padding(padding: const EdgeInsets.only(right: 16.0), child: Text(_controller.status, style: TextStyle(color: Colors.tealAccent[100], fontSize: 12, fontStyle: FontStyle.italic)))),
              if (_controller.isLoading) const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
              IconButton(icon: const Icon(Icons.vpn_key), tooltip: 'Configurações API', onPressed: _showSettings),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // ================== LADO ESQUERDO (Painel Unificado) ==================
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), decoration: const BoxDecoration(color: Colors.black26, border: Border(bottom: BorderSide(color: Colors.white24), right: BorderSide(color: Colors.white24)), borderRadius: BorderRadius.only(topLeft: Radius.circular(8))), child: const Text('Legendas Originais', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center))),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                                decoration: const BoxDecoration(color: Colors.black26, border: Border(bottom: BorderSide(color: Colors.white24)), borderRadius: BorderRadius.only(topRight: Radius.circular(8))),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(child: Text('Tradução', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)),
                                    if (_controller.currentMetadata != null)
                                      IconButton(
                                        icon: Icon(_controller.isEditingRawTranslation ? Icons.close : Icons.paste, size: 20, color: _controller.isEditingRawTranslation ? Colors.redAccent : Colors.white),
                                        tooltip: _controller.isEditingRawTranslation ? 'Cancelar Colagem' : 'Colar JSON Completo',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: _controller.toggleRawEditMode,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: _controller.isEditingRawTranslation
                            ? Row(
                                children: [
                                  Expanded(child: _buildSimpleSubtitleList(_controller.extractedDialogues, 'Nenhuma legenda extraída.')),
                                  const VerticalDivider(width: 1, color: Colors.white24),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        children: [
                                          Expanded(child: TextField(controller: _controller.translationController, maxLines: null, expands: true, style: const TextStyle(fontSize: 13, fontFamily: 'Courier', color: Colors.amberAccent), decoration: const InputDecoration(hintText: 'Cole o array JSON completo aqui...', border: OutlineInputBorder(), filled: true, fillColor: Colors.black12))),
                                          const SizedBox(height: 8),
                                          SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.check), label: const Text('Validar e Aplicar Tradução'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: _handleJsonValidation))
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : _buildSynchronizedList(),
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
                              child: _buildSectionContainer('Informações do vídeo', _controller.currentMetadata == null 
                                ? const Center(child: Text('Nenhum vídeo focado.', style: TextStyle(color: Colors.grey)))
                                : SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Arquivo: ${_controller.currentMetadata!.fileName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(height: 16),
                                      DropdownButtonFormField<SubtitleTrack>(
                                        isExpanded: true,
                                        value: _controller.selectedTrack,
                                        items: _controller.availableTracks.map((t) => DropdownMenuItem(value: t, child: Text(t.toString(), style: const TextStyle(fontSize: 13)))).toList(),
                                        onChanged: (v) => _controller.changeTrack(v!),
                                        decoration: const InputDecoration(labelText: 'Trilha Fonte', border: OutlineInputBorder(), isDense: true),
                                      ),
                                      const SizedBox(height: 16),
                                      TextFormField(controller: _controller.titleController, onChanged: (v) => _controller.currentMetadata!.title = v, decoration: const InputDecoration(labelText: 'Título da Série/Vídeo', border: OutlineInputBorder(), isDense: true)),
                                      const SizedBox(height: 16),
                                      TextFormField(controller: _controller.episodeController, onChanged: (v) => _controller.currentMetadata!.episode = v, decoration: const InputDecoration(labelText: 'Número do Episódio', border: OutlineInputBorder(), isDense: true)),
                                      const SizedBox(height: 20),
                                      if (_controller.currentMetadata!.isTranslated)
                                        Container(padding: const EdgeInsets.all(8), color: Colors.green.withOpacity(0.2), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('Tradução Concluída', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]))
                                    ],
                                  ),
                                )
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSectionContainer('Outros vídeos da pasta', !_controller.isBatchMode || _controller.batchVideos.isEmpty
                                ? const Center(child: Text('Modo Lote inativo.', style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    itemCount: _controller.batchVideos.length,
                                    itemBuilder: (context, index) {
                                      final video = _controller.batchVideos[index];
                                      final isSelected = _controller.currentMetadata?.filePath == video.filePath;
                                      return ListTile(
                                        dense: true,
                                        selected: isSelected,
                                        selectedTileColor: Colors.blueAccent.withOpacity(0.2),
                                        title: Text(video.fileName, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), maxLines: 2, overflow: TextOverflow.ellipsis),
                                        trailing: video.isTranslated ? const Icon(Icons.check, color: Colors.green, size: 18) : null,
                                        onTap: () => _controller.selectVideo(video),
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
                                Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.video_file), label: const Text('Selecionar 1 Vídeo'), onPressed: _controller.isLoading ? null : _controller.pickVideo)),
                                const SizedBox(width: 10),
                                Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.folder), label: const Text('Selecionar Pasta (Lote)'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]), onPressed: _controller.isLoading ? null : _controller.pickFolderAndAnalyze)),
                              ],
                            ),
                            const Divider(color: Colors.white24),
                            Row(
                              children: [
                                Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.auto_fix_high), label: const Text('Traduzir (API)'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent), onPressed: _controller.isLoading || _controller.currentMetadata == null || _controller.currentMetadata!.isTranslated ? null : () => _handleAPIProcess(_controller.currentMetadata!))),
                                const SizedBox(width: 10),
                                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy), label: const Text('Copiar Prompt'), onPressed: _controller.isLoading || _controller.currentMetadata == null || _controller.currentMetadata!.isTranslated ? null : _controller.copyPromptForVideo)),
                                const SizedBox(width: 10),
                                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.save), label: const Text('Salvar .json'), onPressed: _controller.isLoading || _controller.currentMetadata == null || _controller.currentMetadata!.isTranslated ? null : _controller.saveOriginalJsonForVideo)),
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
                                    onPressed: _controller.isLoading || _controller.translatedDialogues.isEmpty || (_controller.currentMetadata?.isTranslated ?? true) ? null : () => _controller.generateManualMKV(_controller.currentMetadata!)
                                  ),
                                ),
                              ],
                            ),
                            if (_controller.isBatchMode) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.batch_prediction), 
                                  label: const Text('PROCESSAR LOTE COMPLETO (Automático)'), 
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
                                  onPressed: _controller.isLoading ? null : _handleBatchFullProcess
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
    );
  }
}