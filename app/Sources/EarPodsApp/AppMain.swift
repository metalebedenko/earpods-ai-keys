import AppKit
import EarPodsCore
import EarPodsMac

@main
enum AppMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--render-preview" {
            guard arguments.count == 2 else {
                fputs("Usage: EarPodsAIKeys --render-preview <directory>\n", stderr)
                exit(2)
            }
            do {
                let coordinator = AppCoordinator.preview()
                try coordinator.renderPreview(to: URL(fileURLWithPath: arguments[1], isDirectory: true))
            } catch {
                fputs("Preview failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        guard arguments.isEmpty else {
            fputs("Unknown arguments. Use --render-preview <directory> for a safe UI preview.\n", stderr)
            exit(2)
        }
        let coordinator = AppCoordinator()
        application.delegate = coordinator
        withExtendedLifetime(coordinator) { application.run() }
    }
}
