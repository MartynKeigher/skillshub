import SkillsHubCore
import SwiftUI

/// Every file the item installs, readable before installing.
struct ContentsSection: View {
    @Bindable var model: DetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Contents").font(.title2.bold())
                if let details = model.details.value {
                    Text("\(details.files.count) files, \(details.totalSize.byteFormatted)")
                        .foregroundStyle(.secondary)
                }
            }
            switch model.details {
            case .idle, .loading:
                ProgressView("Loading the file list…").frame(maxWidth: .infinity, minHeight: 120)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    Button("Try Again") { Task { await model.loadDetails() } }
                }
            case let .loaded(details):
                HSplitView {
                    FileList(details: details, selection: $model.selectedPath)
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 420)
                    FileViewer(model: model, details: details)
                        .frame(minWidth: 360, maxWidth: .infinity)
                }
                .frame(height: 520)
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor))
                }
            }
        }
    }
}

private struct FileList: View {
    let details: ItemDetails
    @Binding var selection: String?

    var body: some View {
        List(details.files, selection: $selection) { file in
            HStack(spacing: 6) {
                Image(systemName: icon(for: file)).foregroundStyle(.secondary).frame(width: 16)
                Text(file.path)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 4)
                let count = details.findings(in: file.path).count
                if count > 0 {
                    let worst = details.findings(in: file.path).map(\.finding.severity).max() ?? .low
                    Image(systemName: worst.icon)
                        .foregroundStyle(worst.color)
                        .help("\(count) findings")
                }
                if file.executable {
                    Image(systemName: "terminal").foregroundStyle(.orange).help("Executable")
                }
            }
            .tag(file.path)
            .help("\(file.path), \(file.size.byteFormatted)")
        }
        .listStyle(.sidebar)
    }

    private func icon(for file: ItemFile) -> String {
        switch file.kind {
        case .doc: "doc.text"
        case .script: "terminal"
        case .data: "curlybraces"
        case .asset: "photo"
        case .archive: "archivebox"
        case .binary: "cpu"
        case .unknown: "doc"
        }
    }
}

private struct FileViewer: View {
    let model: DetailViewModel
    let details: ItemDetails

    var body: some View {
        Group {
            if let file = model.selectedFile {
                VStack(spacing: 0) {
                    HStack {
                        Text(file.path).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(file.size.byteFormatted).foregroundStyle(.secondary)
                        if let url = githubURL(file) {
                            Link(destination: url) { Image(systemName: "arrow.up.forward.square") }
                                .help("Open on GitHub")
                        }
                    }
                    .padding(8)
                    Divider()
                    content(file)
                }
            } else {
                ContentUnavailableView("Select a File", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    @ViewBuilder
    private func content(_ file: ItemFile) -> some View {
        switch model.fileText {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView("Couldn't Load This File", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case let .loaded(.text(lines)):
            CodeView(lines: lines, flagged: flaggedLines(file), focus: model.focusLine)
        case .loaded(.binary):
            ContentUnavailableView("Binary File", systemImage: "cpu",
                                   description: Text("This file can't be shown as text. Binary files can't be reviewed, so they count toward the risk."))
        case let .loaded(.tooLarge(size)):
            ContentUnavailableView("Large File", systemImage: "doc.badge.ellipsis",
                                   description: Text("This file is \(size.byteFormatted), too large to show here. Open it on GitHub to read it."))
        }
    }

    private func flaggedLines(_ file: ItemFile) -> [Int: RiskLevel] {
        details.findings(in: file.path).reduce(into: [:]) { result, located in
            guard let line = located.finding.line else { return }
            result[line] = max(result[line] ?? .low, located.finding.severity)
        }
    }

    private func githubURL(_ file: ItemFile) -> URL? {
        URL(string: "https://github.com/\(file.remote.repo)/blob/\(file.remote.commit)/\(file.remote.path)")
    }
}

/// Text with line numbers, findings marked in the gutter, scrolled to the focused line.
private struct CodeView: View {
    let lines: [String]
    let flagged: [Int: RiskLevel]
    let focus: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        let number = index + 1
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(number)")
                                .foregroundStyle(.tertiary)
                                .frame(width: 44, alignment: .trailing)
                            Text(line.isEmpty ? " " : line)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 8)
                        .background(flagged[number].map { $0.color.opacity(0.18) } ?? Color.clear)
                        .overlay(alignment: .leading) {
                            if let level = flagged[number] {
                                Rectangle().fill(level.color).frame(width: 3)
                            }
                        }
                        .id(number)
                    }
                }
                .padding(.vertical, 6)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: focus) { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let focus else { return }
        withAnimation { proxy.scrollTo(focus, anchor: .center) }
    }
}
