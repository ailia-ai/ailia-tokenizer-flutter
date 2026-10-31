import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/services.dart';
import 'package:ailia_tokenizer/ailia_tokenizer.dart' as ailia_tokenizer_dart;
import 'package:ailia_tokenizer/ailia_tokenizer_model.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _tokens = 'Unknown';
  final _ailiaTokenizerModel = AiliaTokenizerModel();

  @override
  void initState() {
    super.initState();
    _testAiliaTokenizer();
  }

  Future<File> copyFileFromAssets(String path) async {
    final byteData = await rootBundle.load('assets/$path');
    final buffer = byteData.buffer;
    Directory tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;
    var filePath = '$tempPath/$path';
    return File(filePath)
      .writeAsBytes(buffer.asUint8List(byteData.offsetInBytes,
    byteData.lengthInBytes));
  }

  void _testAiliaTokenizer() async{
    File bpeFile = await copyFileFromAssets("sentencepiece.bpe.model");
    _ailiaTokenizerModel.openFile(modelFile: bpeFile.path, ailia_tokenizer_dart.AILIA_TOKENIZER_TYPE_XLM_ROBERTA);
    String text = "Hello world.";
    Int32List tokens = _ailiaTokenizerModel.encode(text);
    setState((){
      _tokens = "$tokens";
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('ailia Tokenizer example app'),
        ),
        body: Center(
          child: Text('Tokens: $_tokens\n'),
        ),
      ),
    );
  }
}
