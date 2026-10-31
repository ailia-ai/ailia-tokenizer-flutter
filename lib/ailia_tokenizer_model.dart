// ailia Tokenizer Utility Class

import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'ailia_tokenizer.dart' as ailia_tokenizer_dart;

/// Loads tokenizer model files and encodes text with the native tokenizer.
class AiliaTokenizerModel {
  late ailia_tokenizer_dart.ailiaTokenizerFFI ailiaTokenizer;
  Pointer<Pointer<ailia_tokenizer_dart.AILIATokenizer>>? ppAiliaTokenizer;
  bool available = false;

  final int ailiaStatusSuccess = 0;

  static String ailiaCommonGetTokenizerPath() {
    // Lets tests and local development point at a specific native build.
    final override = Platform.environment['AILIA_TOKENIZER_LIBRARY'];
    if (override != null && override.isNotEmpty) {
      return override;
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return 'libailia_tokenizer.so';
    }
    if (Platform.isMacOS) {
      return 'libailia_tokenizer.dylib';
    }
    if (Platform.isWindows) {
      return 'ailia_tokenizer.dll';
    }
    return 'internal';
  }

  static DynamicLibrary ailiaCommonGetLibrary(String path) {
    final DynamicLibrary library;
    if (Platform.isIOS) {
      library = DynamicLibrary.process();
    } else {
      library = DynamicLibrary.open(path);
    }
    return library;
  }

  /// Opens a tokenizer of [tokenizerType] with the supplied model or BPE files.
  ///
  /// For Qwen2, load vocab.json and merges.txt, then [addedTokensFile]
  /// (explicit token IDs) and [tokenizerConfigFile] (tokenizer_config.json or
  /// tokenizer.json, which also carries the special attribute).
  void openFile(
    int tokenizerType, {
    String? modelFile,
    String? vocabFile,
    String? mergeFile,
    String? addedTokensFile,
    String? tokenizerConfigFile,
  }) {
    close(); // for reopen

    ailiaTokenizer = ailia_tokenizer_dart.ailiaTokenizerFFI(
      ailiaCommonGetLibrary(ailiaCommonGetTokenizerPath()),
    );
    ppAiliaTokenizer = malloc<Pointer<ailia_tokenizer_dart.AILIATokenizer>>();

    int status = ailiaTokenizer.ailiaTokenizerCreate(
      ppAiliaTokenizer!,
      tokenizerType,
      ailia_tokenizer_dart.AILIA_TOKENIZER_FLAG_NONE,
    );
    if (status != ailiaStatusSuccess) {
      malloc.free(ppAiliaTokenizer!);
      ppAiliaTokenizer = null;
      throw Exception("ailiaTokenizerCreate error $status");
    }
    // The native handle now exists; own it so close() releases it when one
    // of the opens below fails.
    available = true;

    try {
      if (modelFile != null) {
        _open(modelFile, ailiaTokenizer.ailiaTokenizerOpenModelFileA,
            ailiaTokenizer.ailiaTokenizerOpenModelFileW,
            "ailiaTokenizerOpenModelFile");
      }
      if (vocabFile != null) {
        _open(vocabFile, ailiaTokenizer.ailiaTokenizerOpenVocabFileA,
            ailiaTokenizer.ailiaTokenizerOpenVocabFileW,
            "ailiaTokenizerOpenVocabFile");
      }
      if (mergeFile != null) {
        _open(mergeFile, ailiaTokenizer.ailiaTokenizerOpenMergeFileA,
            ailiaTokenizer.ailiaTokenizerOpenMergeFileW,
            "ailiaTokenizerOpenMergeFile");
      }
      if (addedTokensFile != null) {
        _open(addedTokensFile, ailiaTokenizer.ailiaTokenizerOpenAddedTokensFileA,
            ailiaTokenizer.ailiaTokenizerOpenAddedTokensFileW,
            "ailiaTokenizerOpenAddedTokensFile");
      }
      if (tokenizerConfigFile != null) {
        _open(tokenizerConfigFile,
            ailiaTokenizer.ailiaTokenizerOpenTokenizerConfigFileA,
            ailiaTokenizer.ailiaTokenizerOpenTokenizerConfigFileW,
            "ailiaTokenizerOpenTokenizerConfigFile");
      }
    } catch (_) {
      close();
      rethrow;
    }
  }

  void _open(
    String path,
    int Function(Pointer<ailia_tokenizer_dart.AILIATokenizer>, Pointer<Char>)
        openA,
    int Function(Pointer<ailia_tokenizer_dart.AILIATokenizer>, Pointer<WChar>)
        openW,
    String name,
  ) {
    int status;
    if (Platform.isWindows) {
      Pointer<WChar> nativePath = path.toNativeUtf16().cast<WChar>();
      try {
        status = openW(ppAiliaTokenizer!.value, nativePath);
      } finally {
        calloc.free(nativePath);
      }
    } else {
      Pointer<Char> nativePath = path.toNativeUtf8().cast<Char>();
      try {
        status = openA(ppAiliaTokenizer!.value, nativePath);
      } finally {
        calloc.free(nativePath);
      }
    }
    if (status != ailiaStatusSuccess) {
      throw Exception("$name error $status : $path");
    }
  }

  /// Registers model-specific special tokens after opening the tokenizer.
  void addSpecialTokens(List<String> specialTokens) {
    if (!available) {
      return;
    }

    final Pointer<Pointer<Char>> charArray =
        calloc<Pointer<Char>>(specialTokens.length);

    for (int i = 0; i < specialTokens.length; i++) {
      charArray[i] = specialTokens[i].toNativeUtf8().cast<Char>();
    }

    int status = ailiaTokenizer.ailiaTokenizerAddSpecialTokens(
      ppAiliaTokenizer!.value,
      charArray,
      specialTokens.length,
    );

    for (int i = 0; i < specialTokens.length; i++) {
      calloc.free(charArray[i]);
    }
    calloc.free(charArray);

    if (status != ailiaStatusSuccess) {
      throw Exception("ailiaTokenizerAddSpecialTokens error $status");
    }
  }

  /// Releases the native tokenizer. Calling this repeatedly is safe.
  void close() {
    if (!available) {
      return;
    }

    Pointer<ailia_tokenizer_dart.AILIATokenizer> tokenizer =
        ppAiliaTokenizer!.value;
    ailiaTokenizer.ailiaTokenizerDestroy(tokenizer);
    malloc.free(ppAiliaTokenizer!);
    ppAiliaTokenizer = null;

    available = false;
  }

  /// Encodes [text] and returns a copy of the native token IDs. Special
  /// tokens are encoded as plain text (equivalent to ailiaTokenizerEncode).
  Int32List encode(String text) {
    return _encode(text, splitSpecialTokens: true);
  }

  /// Encodes [text] keeping registered special tokens
  /// (equivalent to ailiaTokenizerEncodeWithSpecialTokens).
  Int32List encodeWithSpecialTokens(String text) {
    return _encode(text, splitSpecialTokens: false);
  }

  Int32List _encode(String text, {required bool splitSpecialTokens}) {
    if (!available) {
      throw Exception("Model not opened");
    }

    Pointer<Char> nativeText = text.toNativeUtf8().cast<Char>();
    int status;
    try {
      status = splitSpecialTokens
          ? ailiaTokenizer.ailiaTokenizerEncode(
              ppAiliaTokenizer!.value, nativeText)
          : ailiaTokenizer.ailiaTokenizerEncodeWithSpecialTokens(
              ppAiliaTokenizer!.value, nativeText);
    } finally {
      calloc.free(nativeText);
    }
    if (status != ailiaStatusSuccess) {
      throw Exception("ailiaTokenizerEncode error $status");
    }

    final Pointer<UnsignedInt> count = malloc<UnsignedInt>();
    try {
      count.value = 0;
      status = ailiaTokenizer.ailiaTokenizerGetTokenCount(
        ppAiliaTokenizer!.value,
        count,
      );
      if (status != ailiaStatusSuccess) {
        throw Exception("ailiaTokenizerGetTokenCount error $status");
      }

      final Pointer<Int> tokens = malloc<Int>(max(count.value, 1));
      try {
        status = ailiaTokenizer.ailiaTokenizerGetTokens(
          ppAiliaTokenizer!.value,
          tokens,
          count.value,
        );
        if (status != ailiaStatusSuccess) {
          throw Exception("ailiaTokenizerGetTokens error $status");
        }

        Int32List tokensF = Int32List(count.value);
        for (int i = 0; i < count.value; i++) {
          tokensF[i] = tokens[i];
        }
        return tokensF;
      } finally {
        malloc.free(tokens);
      }
    } finally {
      malloc.free(count);
    }
  }

  /// Decodes [tokens] into text, skipping special tokens
  /// (equivalent to ailiaTokenizerDecode).
  String decode(List<int> tokens) {
    return _decode(tokens, withSpecialTokens: false);
  }

  /// Decodes [tokens] into text, keeping special tokens
  /// (equivalent to ailiaTokenizerDecodeWithSpecialTokens).
  String decodeWithSpecialTokens(List<int> tokens) {
    return _decode(tokens, withSpecialTokens: true);
  }

  String _decode(List<int> tokens, {required bool withSpecialTokens}) {
    if (!available) {
      throw Exception("Model not opened");
    }

    // Keep the data pointer valid for an empty list; the C API rejects NULL.
    final Pointer<Int> nativeTokens = malloc<Int>(max(tokens.length, 1));
    try {
      for (int i = 0; i < tokens.length; i++) {
        nativeTokens[i] = tokens[i];
      }
      int status = withSpecialTokens
          ? ailiaTokenizer.ailiaTokenizerDecodeWithSpecialTokens(
              ppAiliaTokenizer!.value, nativeTokens, tokens.length)
          : ailiaTokenizer.ailiaTokenizerDecode(
              ppAiliaTokenizer!.value, nativeTokens, tokens.length);
      if (status != ailiaStatusSuccess) {
        throw Exception("ailiaTokenizerDecode error $status");
      }
    } finally {
      malloc.free(nativeTokens);
    }

    final Pointer<UnsignedInt> length = malloc<UnsignedInt>();
    try {
      length.value = 0;
      int status = ailiaTokenizer.ailiaTokenizerGetTextLength(
        ppAiliaTokenizer!.value,
        length,
      );
      if (status != ailiaStatusSuccess) {
        throw Exception("ailiaTokenizerGetTextLength error $status");
      }

      final Pointer<Char> text = malloc<Char>(max(length.value, 1));
      try {
        status = ailiaTokenizer.ailiaTokenizerGetText(
          ppAiliaTokenizer!.value,
          text,
          length.value,
        );
        if (status != ailiaStatusSuccess) {
          throw Exception("ailiaTokenizerGetText error $status");
        }
        return text.cast<Utf8>().toDartString();
      } finally {
        malloc.free(text);
      }
    } finally {
      malloc.free(length);
    }
  }
}
