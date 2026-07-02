import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @Environment(\.dismiss) var dismiss
    var onSelect: (URL) -> Void

    @State private var searchText = ""

    var filteredItems: [HistoryItem] {
        if searchText.isEmpty {
            return historyManager.items
        } else {
            return historyManager.items.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.url.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    historyManager.clear()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
            .padding()

            TextField("Search history...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            List {
                ForEach(filteredItems) { item in
                    Button(action: {
                        if let url = URL(string: item.url) {
                            onSelect(url)
                            dismiss()
                        }
                    }) {
                        HStack(spacing: 10) {
                            AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(URL(string: item.url)?.host ?? "")&sz=32")) { image in
                                image.resizable()
                            } placeholder: {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 16, height: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(item.url)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}
