import SwiftUI

/// "What's new": the changelog entries of the given releases, from the CHANGELOG.md built into the app.
struct WhatsNewView: View {
    let releases: [ChangelogRelease]
    let afterUpdate: Bool
    let close: () -> Void
    @ObservedObject private var loc = Loc.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(afterUpdate ? Loc.t("whatsnew.updated", AppInfo.version) : loc["whatsnew.title"])
                        .font(.title2.weight(.semibold))
                    if !loc["whatsnew.english"].isEmpty {
                        Text(loc["whatsnew.english"]).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(releases.indices, id: \.self) { card(releases[$0]) }
                    if releases.isEmpty {
                        Text(loc["whatsnew.empty"])
                    }
                }
            }

            HStack {
                Spacer()
                Button(loc["whatsnew.all"]) {
                    AppDelegate.openUrl("\(AppInfo.changelogUrl)?lang=\(Loc.shared.locale.language.languageCode?.identifier ?? "en")")
                }
                Button(loc["whatsnew.close"], action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 560)
    }

    private func card(_ release: ChangelogRelease) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Loc.t("about.version", release.version)).font(.headline)
                    if let date = formatDate(release.date) {
                        Text("·  " + date).font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(release.sections.indices, id: \.self) { s in
                    let section = release.sections[s]
                    if !section.type.isEmpty {
                        Text(sectionTitle(section.type))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    ForEach(section.items.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            bullet(section.items[i]).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    /// "Added" → "New"/"Nieuw"; unknown types are shown as written.
    private func sectionTitle(_ type: String) -> String {
        let key = "whatsnew.type." + type.lowercased()
        let translated = loc[key]
        return translated == key ? type : translated
    }

    private func bullet(_ item: String) -> Text {
        Changelog.inlineRuns(item).reduce(Text("")) { text, run in
            text + Text(run.text).fontWeight(run.bold ? .semibold : .regular)
        }
    }

    private func formatDate(_ date: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: date) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = loc.locale
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: parsed)
    }
}
