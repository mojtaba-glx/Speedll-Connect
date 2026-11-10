import "../../domain/connection/connection_phase.dart";
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedll_subscription/speedll_subscription.dart';
import '../../domain/engine/android_vpn_engine_adapter.dart';
import '../../domain/engine/connection_engine.dart';
import 'connection_state.dart';

final connectionEngineProvider = Provider<ConnectionEngine>((ref) {
  return AndroidVpnEngineAdapter();
});

final profilesListProvider =
    StateNotifierProvider<ProfilesNotifier, List<ServerProfile>>((ref) {
  return ProfilesNotifier();
});

class ProfilesNotifier extends StateNotifier<List<ServerProfile>> {
  ProfilesNotifier() : super(const []);

  void addProfiles(List<ServerProfile> newProfiles) {
    final existingIds = state.map((p) => p.id).toSet();
    final toAdd = newProfiles.where((p) => !existingIds.contains(p.id)).toList();
    state = [...state, ...toAdd];
  }

  void removeProfile(String id) {
    state = state.where((p) => p.id != id).toList();
  }
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, ConnectionUiState>((ref) {
  final engine = ref.watch(connectionEngineProvider);
  return ConnectionController(engine: engine);
});

class ConnectionController extends StateNotifier<ConnectionUiState> {
  ConnectionController({required this.engine})
      : super(const ConnectionUiState()) {
    _subscription = engine.connectionPhases.listen((phase) {
      state = state.copyWith(phase: phase);
      if (phase == ConnectionPhase.connected) {
        _startTimer();
      } else {
        _stopTimer();
      }
    });
  }

  final ConnectionEngine engine;
  StreamSubscription? _subscription;
  Timer? _timer;

  void selectProfile(ServerProfile profile) {
    state = state.copyWith(activeProfile: profile);
  }

  void _startTimer() {
    _timer?.cancel();
    state = state.copyWith(connectedDuration: Duration.zero);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(
        connectedDuration: state.connectedDuration + const Duration(seconds: 1),
      );
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> toggleConnection() async {
    if (state.isConnected || state.isConnecting) {
      await engine.disconnect();
    } else {
      final profile = state.activeProfile;
      if (profile == null) {
        state = state.copyWith(errorMessage: 'لطفاً ابتدا یک سرور را انتخاب یا اضافه کنید.');
        return;
      }
      try {
        state = state.copyWith(errorMessage: null);
        await engine.connect(profile);
      } catch (e) {
        state = state.copyWith(errorMessage: 'خطا در اتصال: $e');
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
