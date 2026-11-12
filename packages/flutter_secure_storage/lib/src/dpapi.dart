import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptProtectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptProtectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

class Dpapi {
  Dpapi._(this._protect, this._unprotect, this._localFree);

  final _CryptProtectDataDart _protect;
  final _CryptUnprotectDataDart _unprotect;
  final _LocalFreeDart _localFree;

  static Dpapi? _instance;

  static Dpapi get instance => _instance ??= _load();

  static Dpapi _load() {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    return Dpapi._(
      crypt32.lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
        'CryptProtectData',
      ),
      crypt32
          .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
        'CryptUnprotectData',
      ),
      kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree'),
    );
  }

  Uint8List protect(Uint8List plaintext) => _run(plaintext, encrypt: true);

  Uint8List unprotect(Uint8List ciphertext) => _run(ciphertext, encrypt: false);

  Uint8List _run(Uint8List input, {required bool encrypt}) {
    final inputPtr = malloc.allocate<Uint8>(input.isEmpty ? 1 : input.length);
    final inputBlob = malloc<_DataBlob>();
    final outputBlob = malloc<_DataBlob>();
    try {
      if (input.isNotEmpty) {
        inputPtr.asTypedList(input.length).setAll(0, input);
      }
      inputBlob.ref
        ..cbData = input.length
        ..pbData = inputPtr;
      outputBlob.ref
        ..cbData = 0
        ..pbData = nullptr;

      const cryptProtectUiForbidden = 0x1;
      final result = encrypt
          ? _protect(
              inputBlob,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              cryptProtectUiForbidden,
              outputBlob,
            )
          : _unprotect(
              inputBlob,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              cryptProtectUiForbidden,
              outputBlob,
            );

      if (result == 0) {
        throw StateError('DPAPI operation failed');
      }

      final length = outputBlob.ref.cbData;
      if (length == 0 || outputBlob.ref.pbData == nullptr) {
        return Uint8List(0);
      }
      try {
        return Uint8List.fromList(
          outputBlob.ref.pbData.asTypedList(length),
        );
      } finally {
        _localFree(outputBlob.ref.pbData.cast());
      }
    } finally {
      malloc.free(inputPtr);
      malloc.free(inputBlob);
      malloc.free(outputBlob);
    }
  }
}
