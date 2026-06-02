import Foundation
import Network
import Observation

/// Observable network-reachability flag driving the read-through cache's
/// online/offline branch. Root-owned and alive for the whole app session, so it
/// has no teardown — the `NWPathMonitor` runs until the process exits.
@Observable
@MainActor
final class NetworkMonitor {
  /// Optimistically `true` until the first path update resolves, so the very
  /// first lyric load on a fast launch takes the online (revalidating) branch
  /// rather than briefly showing an offline state.
  private(set) var isOnline: Bool = true

  @ObservationIgnored private let monitor = NWPathMonitor()
  @ObservationIgnored private let queue =
    DispatchQueue(label: "com.magicparklabs.Furioke.network-monitor")

  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      Task { @MainActor [weak self] in self?.isOnline = online }
    }
    monitor.start(queue: queue)
  }
}
