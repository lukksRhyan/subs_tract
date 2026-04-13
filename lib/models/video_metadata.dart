class VideoMetadata {
  String fileName;
  String filePath;
  String title;
  String episode;

  VideoMetadata({
    required this.fileName,
    required this.filePath,
    this.title = '',
    this.episode = '',
  });

  factory VideoMetadata.fromPath(String path) {
    String name = path.split('\\').last.split('/').last;
    String cleanTitle = name.contains('.') 
        ? name.substring(0, name.lastIndexOf('.')) 
        : name;

    return VideoMetadata(
      fileName: name,
      filePath: path,
      title: cleanTitle,
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