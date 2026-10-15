import SylviaSourceCLI

/// `sylvia-source` plus test-only fault injection, throttling, connection closing and automatic approval,
/// for the G0.2 part 2 simulator integration runs. Stage 0 test harness only; never shipped.
@main
struct SylviaTestSourceMain {
    static func main() async { await SourceCommandLine.main(testHooks: true) }
}
