import ArgumentParser
import Foundation
import LivekeetCore

struct Projects: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage projects: named groups of recordings sharing a folder.",
        subcommands: [List.self, Create.self, Rename.self], defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List projects and their folders.")
        func run() async throws {
            let projects = try await RecordingLibrary.shared.projects()
            let recordings = try await RecordingLibrary.shared.recordings()
            if projects.isEmpty { print("No projects yet. Use livekeet projects create <name>.") }
            for project in projects {
                print("\(project.name)  (\(recordings.filter(project.contains).count) recordings)\n  \(project.folderURL.path)\n  \(project.id.uuidString)")
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a project or group recordings in an existing folder.")
        @Argument(help: "Project name.") var name: String
        @Option(help: "Project folder; defaults to <output directory>/<project name>.") var folder: String?
        func run() async throws {
            let config = try LivekeetConfig.load()
            let base = URL(fileURLWithPath: NSString(string: config.outputDirectory.isEmpty ? "~/meetings" : config.outputDirectory).expandingTildeInPath)
            let url = folder.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
                ?? RecordingProject.suggestedFolder(name: name, base: base)
            let project = try await RecordingLibrary.shared.createProject(name: name, folder: url)
            print("Created \(project.name): \(project.folderURL.path)")
            try await RecordingLibrary.shared.discover(in: project.folderURL)
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename a project, keeping its folder.")
        @Argument(help: "Existing project name or ID.") var project: String
        @Argument(help: "New name.") var name: String
        func run() async throws {
            let project = try await RecordingLibrary.shared.project(named: project)
            try await RecordingLibrary.shared.renameProject(id: project.id, name: name)
            print("Renamed project to \(name).")
        }
    }
}
