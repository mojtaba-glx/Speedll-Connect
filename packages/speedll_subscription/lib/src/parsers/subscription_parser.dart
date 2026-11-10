import '../models/server_profile.dart';

class ParseResult {
  const ParseResult({
    required this.isSuccess,
    this.profiles = const <ServerProfile>[],
    this.warnings = const <String>[],
    this.errorMessage,
  });

  final bool isSuccess;
  final List<ServerProfile> profiles;
  final List<String> warnings;
  final String? errorMessage;

  factory ParseResult.failure(String message) {
    return ParseResult(
      isSuccess: false,
      errorMessage: message,
    );
  }

  factory ParseResult.success(
    List<ServerProfile> profiles, {
    List<String> warnings = const <String>[],
  }) {
    return ParseResult(
      isSuccess: true,
      profiles: profiles,
      warnings: warnings,
    );
  }
}

abstract interface class SubscriptionParser {
  String get parserName;

  bool canParse(String content);

  Future<ParseResult> parse(String content);
}
