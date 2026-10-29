import Foundation
import Observation
import SkillsHubCore

/// One item's page: its files and findings, and the file being read.
@MainActor
@Observable
final class DetailViewModel {
    enum Loadable<Value> {
        case idle
        case loading
        case loaded(Value)
        case failed(String)

        var value: Value? {
            if case let .loaded(value) = self { return value }
            return nil
        }
    }

    enum FileText {
        case text(lines: [String])
        case tooLarge(Int64)
        case binary
    }

    /// Larger files are listed but not shown, to keep the viewer responsive.
    static let maximumViewableSize: Int64 = 1_000_000

    let itemID: String
    private(set) var details: Loadable<ItemDetails> = .idle
    var selectedPath: String? {
        didSet { if selectedPath != oldValue { Task { await loadSelectedFile() } } }
    }
    /// The line to scroll to, set when a finding is opened.
    var focusLine: Int?
    private(set) var fileText: Loadable<FileText> = .idle

    @ObservationIgnored private let app: AppModel

    init(itemID: String, app: AppModel) {
        self.itemID = itemID
        self.app = app
    }

    var item: CatalogItem? { app.index.catalog?.item(id: itemID) }

    func loadDetails() async {
        guard let catalog = app.index.catalog, let item = catalog.item(id: itemID) else { return }
        if case .loaded = details { return }
        guard item.isReviewable else {
            details = .failed(String(localized: "SkillsFlow couldn't fetch this plugin's files, so there's nothing to show."))
            return
        }
        details = .loading
        do {
            details = .loaded(try await catalog.details(of: item, using: app.details))
        } catch DetailsError.gone, DetailsError.stale {
            // The catalog is older than the published details: get the current one and retry once.
            await app.refreshCatalog()
            guard let fresh = app.index.catalog, let freshItem = fresh.item(id: itemID) else {
                details = .failed(String(localized: "This item is no longer in the catalog."))
                return
            }
            do {
                details = .loaded(try await fresh.details(of: freshItem, using: app.details))
            } catch {
                details = .failed(error.localizedDescription)
            }
        } catch {
            details = .failed(error.localizedDescription)
        }
        if selectedPath == nil, let files = details.value?.files {
            selectedPath = files.first { $0.path.hasSuffix("SKILL.md") }?.path ?? files.first?.path
        }
    }

    func open(_ finding: LocatedFinding) {
        focusLine = finding.finding.line
        selectedPath = finding.path
    }

    var selectedFile: ItemFile? {
        guard let selectedPath else { return nil }
        return details.value?.files.first { $0.path == selectedPath }
    }

    private func loadSelectedFile() async {
        guard let file = selectedFile else {
            fileText = .idle
            return
        }
        if file.kind == .binary || file.kind == .archive || file.kind == .asset {
            fileText = .loaded(.binary)
            return
        }
        if file.size > Self.maximumViewableSize {
            fileText = .loaded(.tooLarge(file.size))
            return
        }
        fileText = .loading
        do {
            let data = try await app.content.contents(of: file.remote)
            guard selectedPath == file.path else { return }
            if data.prefix(8192).contains(0) {
                fileText = .loaded(.binary)
            } else {
                let text = String(decoding: data, as: UTF8.self)
                fileText = .loaded(.text(lines: text.components(separatedBy: "\n")))
            }
        } catch {
            guard selectedPath == file.path else { return }
            fileText = .failed(error.localizedDescription)
        }
    }
}
