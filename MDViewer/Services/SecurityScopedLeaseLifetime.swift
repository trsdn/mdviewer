import Foundation

enum SecurityScopedLeaseLifetime {
    /// Keeps a security-scoped lease alive until an asynchronous operation ends.
    static func retaining<T, Lease: AnyObject>(
        _ lease: Lease,
        operation: () async throws -> T
    ) async rethrows -> T {
        defer { withExtendedLifetime(lease) {} }
        return try await operation()
    }
}
