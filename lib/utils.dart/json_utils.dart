class JsonUtils {
  static String cleanJson(String text) {
    String cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
    int start = cleaned.indexOf('[');
    int end = cleaned.lastIndexOf(']');
    
    if (start != -1 && end != -1) {
      cleaned = cleaned.substring(start, end + 1);
    }
    
    // Sanitizador de tags ASS
    cleaned = cleaned.replaceAll(RegExp(r'\{\\(?!\\)'), r'{\\\\');
    
    return cleaned;
  }
}