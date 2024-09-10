# frame_flutter_stt_host (online speech-to-text, live captioning)

Connects to Frame, streams audio from the Host (phone) microphone (for now - streaming from Frame mic coming), which is sent through a local (on Host device)
Translation via Libretranslate. Transcription with speech_to_text.

Change URL and APIKEY in main.dart:


  Future<String> translateText(String text, String sourceLang, String targetLang) async {
    try {
      var url = Uri.parse('INSERT-LIBRETRANSLATE-URL/translate');
      var response = await http.post(url, headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      }, body: {
        'q': text,
        'source': 'auto',  // Quellsprache automatisch erkennen
        'target': 'de',  // Zielsprache ist Italienisch
        'format': 'text',
        'api_key': 'INSERT-API-KEY',
      });
