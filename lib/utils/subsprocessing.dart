import 'dart:io';
import 'dart:convert';
import 'package:process_run/process_run.dart';
import 'package:path/path.dart' as p;

Future<void> extrairFalasParaJson(String caminhoVideo) async {
  print('Iniciando o processo de extração de falas...');

  // 1. Encontrando e extraindo a legenda em inglês
  final nomeArquivo = p.basenameWithoutExtension(caminhoVideo);
  final legendaAss = '$nomeArquivo.ass';
  final shell = Shell();
  print('1. Extraindo a legenda em inglês...');
  try {
    // ffprobe para encontrar a primeira faixa de legenda (streams:s:0)
    final List<ProcessResult> resultadosExtrair = await shell.run('ffmpeg -i "$caminhoVideo" -map 0:s:0 "$legendaAss"');

    if (resultadosExtrair.any((result) => result.exitCode != 0)) {
      throw Exception('Falha ao extrair a legenda: ${resultadosExtrair.map((result) => result.stderr).join('\n')}');
    }
    print('Legenda salva em: $legendaAss');
  } catch (e) {
    print('Erro: Ocorreu um problema com o ffmpeg. Verifique se o arquivo tem legenda ou se o ffmpeg está no PATH.');
    print(e);
    return;
  }

  // 2. Lendo o arquivo .ass e extraindo as falas
  print('\n2. Lendo o arquivo .ass e extraindo as falas...');
  try {
    final arquivoAss = File(legendaAss);
    final linhas = await arquivoAss.readAsLines();
    final falas = <String>[];

    for (var linha in linhas) {
      if (linha.startsWith('Dialogue:')) {
        // A linha de diálogo no formato ASS tem várias partes separadas por vírgula.
        // O texto da fala é a última parte.
        final partes = linha.split(',');
        if (partes.length > 9) {
          final fala = partes.sublist(9).join(',').replaceAll(RegExp(r'\{.*?\}'), '').trim();
          if (fala.isNotEmpty) {
            falas.add(fala);
          }
        }
      }
    }

    if (falas.isEmpty) {
      print('Aviso: Nenhuma fala foi encontrada no arquivo .ass.');
      return;
    }

    // 3. Gerando o arquivo JSON
    print('\n3. Gerando o arquivo JSON...');
    final nomeJson = '$nomeArquivo.json';
    final jsonOutput = jsonEncode(falas);

    final arquivoJson = File(nomeJson);
    await arquivoJson.writeAsString(jsonOutput);

    print('Falas salvas com sucesso em: $nomeJson');

  } catch (e) {
    print('Erro: Falha ao processar o arquivo .ass.');
    print(e);
  }
}

void main() {
  final caminhoDoVideo = 'seu_video.mkv'; // Substitua pelo caminho do seu arquivo de vídeo.
  extrairFalasParaJson(caminhoDoVideo);
}