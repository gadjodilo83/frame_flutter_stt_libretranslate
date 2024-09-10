import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:buffered_list_stream/buffered_list_stream.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;

import 'frame_helper.dart';
import 'simple_frame_app.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState {
  late stt.SpeechToText _speechToText;
  bool _isAvailable = false;
  bool _isListening = false;
  String _translatedText = "";
  static const _textStyle = TextStyle(fontSize: 30);
  String _selectedInputLanguage = 'de'; 
  String _selectedTargetLanguage = 'it'; 

  final List<String> _languages = ['en', 'de', 'it', 'fr', 'es', 'auto'];
  final ScrollController _scrollController = ScrollController();

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    _speechToText = stt.SpeechToText();
    currentState = ApplicationState.initializing;
    _initSpeechRecognition();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initSpeechRecognition() async {
    _isAvailable = await _speechToText.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          setState(() {});
          _restartListening();
        }
      },
      onError: (error) {
        _log.severe('Speech Recognition Error: $error');
      },
    );
    currentState = ApplicationState.disconnected;
    if (mounted) setState(() {});
  }

  void _startListening() async {
    if (_isAvailable && !_isListening) {
      _translatedText = '';
      setState(() {});

      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            // Übersetze und zeige den Text fortlaufend an
            _translateAndSendTextToFrame(result.recognizedWords);
          });
        },
        localeId: _selectedInputLanguage,
      );
      _isListening = true;
      setState(() {});
    }
  }

  void _stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      _isListening = false;
      setState(() {});
    }
  }

  void _restartListening() {
    if (!_isListening) {
      _startListening();
    }
  }

  void _translateAndSendTextToFrame(String text) async {
    if (text.isNotEmpty) {
      try {
        String translatedText = await translateText(text, _selectedInputLanguage, _selectedTargetLanguage);

        // Übersetzter Text wird live auf dem Frame angezeigt
        _log.info('Sending translated text to frame: $translatedText');
        _sendTextToFrame(translatedText);
        setState(() {
          _translatedText = translatedText;
        });
      } catch (e) {
        _log.severe('Fehler beim Senden des übersetzten Textes an das Frame: $e');
      }
    }
  }

  Future<String> translateText(String text, String sourceLang, String targetLang) async {
    try {
      var url = Uri.parse('URL_TO_LIBRETRANSLATE/translate');
      var response = await http.post(url, headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      }, body: {
        'q': text,
        'source': sourceLang,
        'target': targetLang,
        'format': 'text',
        'api_key': 'LIBRETRANSLATE_APIKEY',
      });

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        _log.info('Translation successful: ${data['translatedText']}');
        return data['translatedText'];
      } else {
        _log.severe('Failed to translate text: ${response.body}');
        return text;
      }
    } catch (e) {
      _log.severe('Error translating text: $e');
      return text;
    }
  }

  Future<void> _sendTextToFrame(String text) async {
    if (text.isNotEmpty) {
      try {
        String wrappedText = FrameHelper.wrapText(text, 640, 4);
        int sentBytes = 0;
        int bytesRemaining = wrappedText.length;
        int chunksize = frame!.maxDataLength! - 1;
        List<int> bytes;

        while (sentBytes < wrappedText.length) {
          if (bytesRemaining <= chunksize) {
            bytes = [0x0b] + wrappedText.substring(sentBytes, sentBytes + bytesRemaining).codeUnits;
          } else {
            bytes = [0x0a] + wrappedText.substring(sentBytes, sentBytes + chunksize).codeUnits;
          }

          frame!.sendData(bytes);
          sentBytes += bytes.length;
          bytesRemaining = wrappedText.length - sentBytes;
        }
      } catch (e) {
        _log.severe('Fehler beim Senden des Textes an das Frame: $e');
      }
    }
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    _translatedText = '';
    if (mounted) setState(() {});

    _startListening();
  }

  @override
  Future<void> cancel() async {
    _stopListening();
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speech-to-Text',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Frame Speech-to-Text"),
          actions: [getBatteryWidget()],
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_translatedText, style: _textStyle),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      DropdownButton<String>(
                        value: _selectedInputLanguage,
                        items: _languages
                            .map((lang) => DropdownMenuItem<String>(
                                  value: lang,
                                  child: Text(lang.toUpperCase()),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedInputLanguage = value!;
                          });
                        },
                        hint: const Text("Input Language"),
                      ),
                      DropdownButton<String>(
                        value: _selectedTargetLanguage,
                        items: _languages
                            .map((lang) => DropdownMenuItem<String>(
                                  value: lang,
                                  child: Text(lang.toUpperCase()),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedTargetLanguage = value!;
                          });
                        },
                        hint: const Text("Target Language"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(
          const Icon(Icons.mic),
          const Icon(Icons.mic_off),
        ),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}
