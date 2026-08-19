import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: HistoryPanelModel
    @ObservedObject var store: HistoryStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if model.visible.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 420)
        .background(.ultraThinMaterial)
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, item in
                        HistoryRow(
                            item: item,
                            shortcut: model.shortcuts[item.id],
                            selected: item.id == model.selectedID,
                            thumbnail: item.kind == .image ? store.image(for: item) : nil
                        )
                        .overlay(alignment: .bottom) {
                            // Hairline between the pinned block and the rest.
                            if item.pinned, index + 1 < model.visible.count,
                               !model.visible[index + 1].pinned {
                                Divider().padding(.top, 6)
                            }
                        }
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedID = item.id
                            model.confirmSelection()
                        }
                        .contextMenu {
                            Button(item.pinned ? "Unpin" : "Pin") {
                                model.selectedID = item.id
                                model.togglePinSelection()
                            }
                            Button("Delete") {
                                model.selectedID = item.id
                                model.deleteSelection()
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clipboard")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "History is empty" : "Nothing found")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            hint("↩", "paste")
            hint("⌘1…9", "quick pick")
            hint("⌘P", "pin")
            hint("⌘A…", "pinned")
            hint("⌘⌫", "delete")
            Spacer()
            Text("\(model.visible.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct HistoryRow: View {
    let item: ClipItem
    let shortcut: String?
    let selected: Bool
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: item.symbolName)
                    .frame(width: 34)
                    .foregroundStyle(selected ? .white : .secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 13))
                if let app = item.appName {
                    Text(app)
                        .font(.system(size: 10))
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                }
            }

            Spacer(minLength: 4)

            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
            }
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.clear)
        )
    }
}
