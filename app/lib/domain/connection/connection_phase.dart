/// UI-safe connection lifecycle states. These are not engine-specific states.
enum ConnectionPhase {
  disconnected,
  preparing,
  connecting,
  connected,
  reconnecting,
  disconnecting,
  failed,
}
