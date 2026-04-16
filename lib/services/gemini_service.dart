import 'dart:convert';
import 'package:SubsTract/utils/json_utils.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static Future<String> translateSubtitles({
    required List<String> dialogues,
    required String apiKey,
  }) async {
    final model = GenerativeModel(model: 'models/gemini-2.5-flash', apiKey: apiKey);
    
    final prompt = "Translate this anime subtitle JSON array to Brazilian Portuguese. "
        "CRITICAL RULES FOR JSON VALIDITY: "
        "1. If the dialogue contains double quotes (\"), replace them with single quotes (') inside the text. "
        "2. You MUST escape backslashes in ASS style tags. For example, {\\pos(x,y)} MUST be written as {\\\\pos(x,y)} in the JSON. "
        "Return ONLY the translated JSON array:\n\n"
        "${jsonEncode(dialogues)}";

    final response = await model.generateContent([Content.text(prompt)]);
    final cleanedJsonStr = JsonUtils.cleanJson(response.text ?? '');
    
    // Testa se o JSON é válido
    jsonDecode(cleanedJsonStr); 
    
    return cleanedJsonStr;
  }
}