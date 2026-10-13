import Testing

/// Every suite that drives real AVFoundation playback, decoding or export is nested here, so they run one at a
/// time: concurrent players would distort the timing measurements. Unit suites over fakes run in parallel.
@Suite("Real AVFoundation (serialized)", .serialized, .temporaryStores)
enum RealAV {}
