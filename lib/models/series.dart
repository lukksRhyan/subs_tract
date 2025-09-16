class Series {
  String? title;
  String? description;
  List<Episode>? episodes;
}
class Episode{
  final String title;
  final String description;
  final Subtitle subtitle;

  Episode({
    required this.title,
    required this.description,
    required this.subtitle,
  });
}
class Subtitle {
    String? language;
    String? series;
    int? episode;//00 = Unique
    List<String>? dialogs;

    Subtitle({this.language, this.series, this.episode, this.dialogs});
}
