import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/engine/connection_engine.dart';
import '../../domain/profiles/server_profile.dart';
import 'connection_state.dart';

final connectionEngineProvider = Provider<ConnectionEngine?>((ref) => null);

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, ConnectionUiState>((ref) {
  final engine = ref.watch(connectionEngineProvider);
  return ConnectionController(engine: engine);
});

class ConnectionController extends StateNotifier<ConnectionUiState> {
  ConnectionController({this.engine}) : super(const ConnectionUiState());

  final ConnectionEngine? engine;

  void selectProfile(ServerProfile profile) {
    state = state.copyWith(activeProfile: profile);
  }

  Future<void> toggleConnection() async {
    if (engine == null) {
      // Per AGENTS.md rules: do not simulate a fake successful connection.
      return;
    }
  }
}
