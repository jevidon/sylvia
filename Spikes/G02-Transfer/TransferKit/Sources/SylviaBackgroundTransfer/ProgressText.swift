import Foundation
import SylviaTransferCore

/// Byte counts for the transfer screen (plan 15.5: "3.1 of 5.2 GB verified").
///
/// "Received" counts bytes that arrived (including parts not yet checked); "verified" counts only parts
/// whose SHA-256 matched and that are on disk. Values are rounded down, so a count never reaches the
/// total on screen before it does in fact: "5.2 of 5.2 GB verified" appears only when every byte is
/// verified. Decimal units (1 GB = 10^9 bytes), as Files and Settings show sizes.
///
/// Harness wording only; product strings come from the design package's status vocabulary (plan 4.4.6).
public enum ProgressText {
    public static func verified(_ progress: TransferProgress) -> String {
        "\(fraction(progress.verifiedBytes, of: progress.totalBytes)) verified"
    }

    public static func received(_ progress: TransferProgress) -> String {
        "\(fraction(progress.receivedBytes, of: progress.totalBytes)) received"
    }

    /// "<done> of <total> <unit>", with `done` rounded down and never equal to `total` unless complete.
    public static func fraction(_ done: Int64, of total: Int64) -> String {
        let (divisor, unit) = scale(total)
        if divisor == 1 { return "\(min(done, total)) of \(total) \(unit)" }
        let totalTenths = Int64((Double(total) / Double(divisor) * 10).rounded())
        var doneTenths = Int64((Double(min(done, total)) / Double(divisor) * 10).rounded(.down))
        if done < total, doneTenths >= totalTenths { doneTenths = max(0, totalTenths - 1) }
        if done >= total { doneTenths = totalTenths }
        return "\(tenths(doneTenths)) of \(tenths(totalTenths)) \(unit)"
    }

    static func scale(_ total: Int64) -> (Int64, String) {
        switch total {
        case 1_000_000_000...: (1_000_000_000, "GB")
        case 1_000_000...: (1_000_000, "MB")
        case 1_000...: (1_000, "KB")
        default: (1, "bytes")
        }
    }

    static func tenths(_ value: Int64) -> String { "\(value / 10).\(value % 10)" }
}
