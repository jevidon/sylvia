import SylviaSourceCLI

/// The command-line Mac source (G0.2). It has no test hooks; `sylvia-test-source` adds those.
@main
struct SylviaSourceMain {
    static func main() async { await SourceCommandLine.main(testHooks: false) }
}
