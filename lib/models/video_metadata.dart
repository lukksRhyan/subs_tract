class VideoMetadata {
  String fileName;
  String filePath;
  String title;
  String episode;
  List<SubtitleTrack> availableTracks;
  SubtitleTrack? selectedTrack;

  VideoMetadata({
    required this.fileName,
    required this.filePath,
    this.title = '',
    this.episode = '',
    this.availableTracks = const [],
    this.selectedTrack,
  });

  factory VideoMetadata.fromPath(String path) {
    String name = path.split('\\').last.split('/').last;
    String cleanTitle = name.contains('.') 
        ? name.substring(0, name.lastIndexOf('.')) 
        : name;

    // Tenta extrair o episódio do nome do arquivo (ex: "Anime S01E03" -> "03")
    String ep = '';
    RegExp epRegex = RegExp(r'(?:E|Ep|- |0)(\d{1,3})(?=\D|$)');
    Match? match = epRegex.firstMatch(cleanTitle);
    if (match != null) {
      ep = match.group(1) ?? '';
    }

    return VideoMetadata(
      fileName: name,
      filePath: path,
      title: cleanTitle,
      episode: ep,
      availableTracks: [],
    );
  }
}

class SubtitleTrack {
  final int index;
  final String language;
  final String? title;

  SubtitleTrack({required this.index, required this.language, this.title});

  @override
  String toString() => 'Faixa $index - ${language.toUpperCase()} ${title ?? ""}';
}