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
  String _partialResult = "N/A";
  String _finalResult = "N/A";
  static const _textStyle = TextStyle(fontSize: 30);

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
    super.dispose();
  }

  void _initSpeechRecognition() async {
    _isAvailable = await _speechToText.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          setState(() {});
          _restartListening(); // Automatically restart when the status is 'done' or 'notListening'
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
      _finalResult = '';
      _partialResult = '';
      setState(() {});

      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _partialResult = result.recognizedWords;
            if (result.finalResult) {
              _finalResult = _partialResult;
              _partialResult = '';
              _sendTextToFrame(_finalResult);  // Text wird an Frame gesendet
            }
          });
        },
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

  void _restartListening() async {
    // Restart the listening process automatically when stopped
    if (!_isListening) {
      Future.delayed(const Duration(seconds: 1), () {
        _startListening();
      });
    }
  }


// Function to translate text using LibreTranslate API
Future<String> translateText(String text, String sourceLang, String targetLang) async {
  try {
    var url = Uri.parse('URL-TO-LIBRETRANSLATE/translate');
    var response = await http.post(url, headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    }, body: {
      'q': text,
      'source': sourceLang,
      'target': targetLang,
      'format': 'text',
      'api_key': 'LIBRETRANSLATE-API-KEY',
    });

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['translatedText'];
    } else {
      _log.severe('Failed to translate text: ${response.body}');
      return text;  // Return original text if translation fails
    }
  } catch (e) {
    _log.severe('Error translating text: $e');
    return text;
  }
}



void _sendTextToFrame(String text) async {
  if (text.isNotEmpty) {
    try {
      // Translate the text before sending to the frame
      String translatedText = await translateText(text, 'de', 'it');  // Example: Translating from German to Italian

      // Wrap the translated text to send it in chunks
      String wrappedText = FrameHelper.wrapText(translatedText, 640, 4);

      int sentBytes = 0;
      int bytesRemaining = wrappedText.length;
      int chunksize = frame!.maxDataLength! - 1;
      List<int> bytes;

      while (sentBytes < wrappedText.length) {
        if (bytesRemaining <= chunksize) {
          // Final chunk
          bytes = [0x0b] + wrappedText.substring(sentBytes, sentBytes + bytesRemaining).codeUnits;
        } else {
          // Non-final chunk
          bytes = [0x0a] + wrappedText.substring(sentBytes, sentBytes + chunksize).codeUnits;
        }

        // Send the chunk
        frame!.sendData(bytes);

        sentBytes += bytes.length;
        bytesRemaining = wrappedText.length - sentBytes;
      }
    } catch (e) {
      _log.severe('Error sending translated text to Frame: $e');
    }
  }
}




  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    _partialResult = '';
    _finalResult = '';
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
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Align(alignment: Alignment.centerLeft,
                  child: Text('Partial: $_partialResult', style: _textStyle)
                ),
                const Divider(),
                Align(alignment: Alignment.centerLeft,
                  child: Text('Final: $_finalResult', style: _textStyle)
                ),
              ],
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
