import SwiftUI

// MARK: - Data model

struct SongPairing: Codable {
    let title:  String
    let artist: String
    let reason: String   // why it works musically
    let type:   String   // "before" | "after" | "blend"
}

struct SongIntel: Codable {
    let genre:          String
    let subgenre:       String
    let year:           String?
    let moodTags:       [String]
    let vocalType:      String      // "instrumental" | "minimal" | "vocal" | "vocal-forward"
    let introBar:       Int?
    let firstDropBar:   Int?
    let breakdownBar:   Int?
    let secondDropBar:  Int?
    let outroBar:       Int?
    let totalBars:      Int?
    let mixInTip:       String
    let mixOutTip:      String
    let eqTip:          String
    let crowdTip:       String
    let beforeBpmRange: String?
    let afterBpmRange:  String?
    let firstTimeGuide: String
    let verdict:        String
    let pairings:       [SongPairing]
}

// MARK: - Service

enum SongIntelService {

    static func analyse(song: Song) async -> SongIntel? {
        guard let claudePath = BPMService.findClaude() else { return nil }

        let hasLocalData = song.energy != nil || song.danceability != nil || song.bpm != nil

        var lines: [String] = [
            "Track: \"\(song.title)\" by \(song.artist)"
        ]
        if let bpm = song.bpm          { lines.append("BPM: \(bpm)") }
        if let key = song.key          {
            let kstr = song.musicalKey.map { "\(key) (\($0))" } ?? key
            lines.append("Key: \(kstr)")
        }
        if let e = song.energy         { lines.append("Energy: \(String(format: "%.1f", e))/10") }
        if let d = song.danceability   { lines.append("Danceability: \(String(format: "%.1f", d))/10") }
        if let l = song.loudnessDb     { lines.append("Loudness: \(String(format: "%.1f", l)) dBFS") }
        if let t = song.tempoStability { lines.append("Tempo stability: \(String(format: "%.2f", t))") }
        if let ms = song.durationMs {
            lines.append("Duration: \(ms / 60000):\(String(format: "%02d", (ms % 60000) / 1000))")
        }
        if let sid = song.spotifyId    { lines.append("Spotify ID: \(sid)") }

        let context = lines.joined(separator: "\n")

        let dataNote = hasLocalData
            ? "Local audio analysis data is included above (from librosa). Use web search to verify and enrich."
            : "No local audio analysis — this is a Spotify-only track. You MUST use web search to find the real BPM, musical key, release year, energy character, and song structure. Check Tunebat (tunebat.com), Beatport, 1001Tracklists, or any music database."

        let prompt = """
        You are an expert DJ and music analyst with deep knowledge of electronic, dance, and club music. Think like a working DJ who needs to know exactly how and when to play this track.

        \(dataNote)

        \(context)

        Return ONLY a single raw JSON object — no markdown, no explanation:
        {
          "genre": "<primary genre>",
          "subgenre": "<subgenre or same as genre>",
          "year": "<release year or null>",
          "mood_tags": ["<3–4 specific mood words>"],
          "vocal_type": "<instrumental | minimal | vocal | vocal-forward>",
          "intro_bar": <integer: where intro ends and main groove starts, or null>,
          "first_drop_bar": <integer: bar where energy first peaks, or null>,
          "breakdown_bar": <integer: bar of main breakdown, or null>,
          "second_drop_bar": <integer: bar of second drop if any, or null>,
          "outro_bar": <integer: where outro begins, or null>,
          "total_bars": <integer: total bar count, or null>,
          "mix_in_tip": "<actionable cue: which bar to blend in, what sonic element signals the moment — max 65 chars>",
          "mix_out_tip": "<actionable cue: where to start exiting — max 65 chars>",
          "eq_tip": "<one specific EQ move for mixing — max 65 chars>",
          "crowd_tip": "<one sentence: crowd type and set moment this fits — max 90 chars>",
          "before_bpm_range": "<BPM range e.g. 118-122 or null>",
          "after_bpm_range": "<BPM range e.g. 124-128 or null>",
          "first_time_guide": "<2–3 sentences: key moments and elements to listen for, surprises, signature sounds — max 220 chars>",
          "verdict": "<one sentence DJ verdict: strongest use case — max 110 chars>",
          "pairings": [
            {
              "title": "<exact real track title>",
              "artist": "<exact real artist name>",
              "reason": "<why it works: key compatibility, BPM match, energy flow, vibe — max 80 chars>",
              "type": "<before | after | blend>"
            }
          ]
        }

        For pairings: give 4–5 REAL, well-known tracks that DJs commonly play alongside this song. Mix types: some 'before' (what leads into it), some 'after' (what follows it), some 'blend' (what works simultaneously or as a short blend). Be specific and accurate — real track titles and artists only.
        """

        return await Task.detached(priority: .utility) {
            guard let output = shell(claudePath, args: [
                "--output-format", "text",
                "--dangerously-skip-permissions",
                "-p", prompt,
            ]) else { return nil }
            return parse(from: output)
        }.value
    }

    private static func parse(from text: String) -> SongIntel? {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}"),
              let data  = String(text[start...end]).data(using: .utf8),
              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        func str(_ k: String) -> String {
            (obj[k] as? String) ?? "—"
        }
        func optStr(_ k: String) -> String? {
            guard let s = obj[k] as? String, s != "null", !s.isEmpty, s != "—" else { return nil }
            return s
        }
        func optInt(_ k: String) -> Int? {
            if let n = obj[k] as? Int    { return n }
            if let d = obj[k] as? Double { return Int(d) }
            return nil
        }
        let moods = (obj["mood_tags"] as? [Any] ?? []).compactMap { $0 as? String }

        let pairings = (obj["pairings"] as? [[String: Any]] ?? []).compactMap { p -> SongPairing? in
            guard let title  = p["title"]  as? String,
                  let artist = p["artist"] as? String,
                  let reason = p["reason"] as? String,
                  let type   = p["type"]   as? String
            else { return nil }
            return SongPairing(title: title, artist: artist, reason: reason, type: type)
        }

        return SongIntel(
            genre:          str("genre"),
            subgenre:       str("subgenre"),
            year:           optStr("year"),
            moodTags:       moods,
            vocalType:      str("vocal_type"),
            introBar:       optInt("intro_bar"),
            firstDropBar:   optInt("first_drop_bar"),
            breakdownBar:   optInt("breakdown_bar"),
            secondDropBar:  optInt("second_drop_bar"),
            outroBar:       optInt("outro_bar"),
            totalBars:      optInt("total_bars"),
            mixInTip:       str("mix_in_tip"),
            mixOutTip:      str("mix_out_tip"),
            eqTip:          str("eq_tip"),
            crowdTip:       str("crowd_tip"),
            beforeBpmRange: optStr("before_bpm_range"),
            afterBpmRange:  optStr("after_bpm_range"),
            firstTimeGuide: str("first_time_guide"),
            verdict:        str("verdict"),
            pairings:       pairings
        )
    }

    private static func shell(_ path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }
}

// MARK: - Main panel

struct SongIntelView: View {
    let song:      Song
    let onDismiss: () -> Void

    @EnvironmentObject var crateState: CrateState

    enum LoadState { case idle, loading, done, failed }
    @State private var loadState: LoadState = .idle
    @State private var intel:     SongIntel? = nil

    private var durationStr: String {
        guard let ms = song.durationMs, ms > 0 else { return "—" }
        let m = ms / 60000; let s = (ms % 60000) / 1000
        return "\(m):\(String(format: "%02d", s))"
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Rectangle().fill(Color.cratesBorder).frame(height: 1)
            panelBody
        }
        .background(Color(hex: "#090909"))
        .onAppear {
            if intel == nil, let cached = crateState.songIntelCache[song.id] {
                intel = cached; loadState = .done
            }
        }
    }

    // MARK: Header

    private var panelHeader: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.cratesAccent)
                .frame(width: 3)

            HStack(spacing: 8) {
                TrackAvatar(title: song.title, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.cratesPrimary)
                        .lineLimit(1)
                    Text(song.artist.isEmpty ? "—" : song.artist)
                        .font(.system(size: 9))
                        .foregroundColor(.cratesDim)
                        .lineLimit(1)
                }

                Spacer()

                // Quick stat chips
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        if let bpm = song.bpm {
                            siloChip("\(bpm)", unit: "BPM", color: .cratesAccent)
                        }
                        if let key = song.key {
                            siloChip(key, unit: nil, color: .cratesKey)
                        }
                    }
                    if durationStr != "—" {
                        Text(durationStr)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.cratesGhost)
                    }
                }

                // Analyse / refresh + close
                VStack(spacing: 4) {
                    if loadState != .loading {
                        Button { Task { await runAnalysis() } } label: {
                            Image(systemName: loadState == .done ? "arrow.clockwise" : "sparkle")
                                .font(.system(size: 9))
                                .foregroundColor(loadState == .done ? .cratesDim : .cratesAccent)
                                .frame(width: 20, height: 20)
                                .background(Color.cratesElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .help(loadState == .done ? "Re-analyse" : "Deep analyse this track")
                    } else {
                        SongScanPulse()
                    }

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.cratesDim)
                            .frame(width: 20, height: 20)
                            .background(Color.cratesElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .frame(height: 58)
        .background(Color(hex: "#090909"))
    }

    @ViewBuilder
    private func siloChip(_ value: String, unit: String?, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(color)
            if let unit {
                Text(unit)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(color.opacity(0.45))
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    // MARK: Body

    @ViewBuilder
    private var panelBody: some View {
        switch loadState {
        case .idle:    idleView
        case .loading: loadingView
        case .failed:  failedView
        case .done:
            if let intel {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        technicalGrid
                        sectionDivider
                        GenreMoodSection(intel: intel)
                        sectionDivider
                        StructureSection(intel: intel)
                        sectionDivider
                        MixCuesSection(intel: intel)
                        sectionDivider
                        KeyContextSection(song: song)
                        sectionDivider
                        GuideSection(intel: intel)
                        if !intel.pairings.isEmpty {
                            sectionDivider
                            PairingsSection(pairings: intel.pairings)
                        }
                        Spacer().frame(height: 24)
                    }
                }
            }
        }
    }

    // MARK: Technical grid (2 × 2)

    private var technicalGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 1
        ) {
            SongTechCell(
                label: "ENERGY",
                value: song.energy.map { String(format: "%.1f", $0) } ?? "—",
                unit: "/10",
                fill:  song.energy.map { $0 / 10.0 } ?? 0,
                color: energyColor
            )
            SongTechCell(
                label: "DANCEABILITY",
                value: song.danceability.map { String(format: "%.1f", $0) } ?? "—",
                unit: "/10",
                fill:  song.danceability.map { $0 / 10.0 } ?? 0,
                color: .cratesKey
            )
            SongTechCell(
                label: "LOUDNESS",
                value: song.loudnessDb.map { String(format: "%.0f", $0) } ?? "—",
                unit: "dB",
                fill:  song.loudnessDb.map { max(0, min(1, ($0 + 60) / 60)) } ?? 0,
                color: .cratesAccent
            )
            SongTechCell(
                label: "TEMPO STABILITY",
                value: song.tempoStability.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                unit: nil,
                fill:  song.tempoStability ?? 0,
                color: .cratesLive
            )
        }
        .padding(1)
        .background(Color.cratesBorder)
    }

    private var energyColor: Color {
        guard let e = song.energy else { return .cratesAccent }
        if e < 4 { return .cratesKey }
        if e < 7 { return .cratesAccent }
        return Color(hex: "#FF2200")
    }

    private var sectionDivider: some View {
        Rectangle().fill(Color.cratesBorder).frame(height: 1)
    }

    // MARK: Idle / loading / failed

    private var idleView: some View {
        VStack(spacing: 0) {
            if song.energy != nil || song.bpm != nil {
                technicalGrid
                sectionDivider
            }
            VStack(spacing: 14) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.cratesGhost)
                VStack(spacing: 5) {
                    Text("DEEP TRACK ANALYSIS")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.cratesDim)
                    Text("Structure · Mix cues · Crowd fit\nKey compat · Works well with")
                        .font(.system(size: 9))
                        .foregroundColor(.cratesGhost)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                Button { Task { await runAnalysis() } } label: {
                    Text("ANALYSE TRACK")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(Color(hex: "#090909"))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color.cratesAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            Spacer()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 0) {
            if song.energy != nil || song.bpm != nil {
                technicalGrid
                sectionDivider
            }
            VStack(spacing: 18) {
                SongScanBarsView().frame(width: 200, height: 32)
                Text("CLAUDE IS LISTENING…")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.cratesAccent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var failedView: some View {
        VStack(spacing: 0) {
            if song.energy != nil || song.bpm != nil {
                technicalGrid
                sectionDivider
            }
            VStack(spacing: 12) {
                Text("ANALYSIS FAILED")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.cratesDim)
                Button { Task { await runAnalysis() } } label: {
                    Text("RETRY")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "#090909"))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.cratesAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            Spacer()
        }
    }

    // MARK: Analysis trigger

    @MainActor
    private func runAnalysis() async {
        loadState = .loading
        if let result = await SongIntelService.analyse(song: song) {
            intel     = result
            loadState = .done
            crateState.cacheSongIntel(result, for: song.id)
        } else {
            loadState = .failed
        }
    }
}

// MARK: - Tech cell

private struct SongTechCell: View {
    let label: String
    let value: String
    let unit:  String?
    let fill:  Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 6, weight: .black, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.cratesGhost)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(fill > 0 ? color : .cratesGhost)
                if let unit {
                    Text(unit)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(color.opacity(0.45))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.cratesElevated)
                    Rectangle()
                        .fill(color.opacity(0.65))
                        .frame(width: geo.size.width * CGFloat(min(fill, 1.0)))
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(hex: "#0D0D0D"))
    }
}

// MARK: - Genre / Mood / Vocal

private struct GenreMoodSection: View {
    let intel: SongIntel

    private var vocalIcon: String {
        switch intel.vocalType {
        case "instrumental":  return "music.note"
        case "minimal":       return "mouth"
        case "vocal":         return "mic"
        case "vocal-forward": return "mic.fill"
        default:              return "questionmark"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            songIntelLabel("TRACK DNA")

            HStack(spacing: 5) {
                Text(intel.genre.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.cratesAccent)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.cratesAccent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                if intel.subgenre != "—" && intel.subgenre != intel.genre {
                    Text(intel.subgenre.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.cratesDim)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.cratesElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                if let year = intel.year {
                    Text(year)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.cratesGhost)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(intel.moodTags, id: \.self) { tag in
                        Text(tag.lowercased())
                            .font(.system(size: 8).italic())
                            .foregroundColor(.cratesKey.opacity(0.85))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.cratesKey.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.cratesKey.opacity(0.18), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }

                    HStack(spacing: 3) {
                        Image(systemName: vocalIcon).font(.system(size: 7))
                        Text(intel.vocalType.replacingOccurrences(of: "-", with: " "))
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.cratesDim)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.cratesElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Structure timeline

private struct StructureSection: View {
    let intel: SongIntel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                songIntelLabel("STRUCTURE")
                Spacer()
                if let total = intel.totalBars {
                    Text("\(total) BARS")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.cratesGhost)
                }
            }

            StructureTimeline(intel: intel)
                .frame(height: 42)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StructureTimeline: View {
    let intel: SongIntel

    var body: some View {
        Canvas { ctx, size in
            let w      = size.width
            let barH   = size.height - 14
            let total  = CGFloat(intel.totalBars ?? 128)

            func xf(_ bar: Int) -> CGFloat { CGFloat(bar) / total * w }

            let introEnd  = intel.introBar      ?? (intel.firstDropBar.map { max(1, $0 - 1) } ?? 16)
            let drop1     = intel.firstDropBar   ?? introEnd
            let breakdown = intel.breakdownBar   ?? Int(total * 0.65)
            let drop2     = intel.secondDropBar  ?? breakdown
            let outro     = intel.outroBar       ?? Int(total * 0.875)
            let end       = Int(total)

            let segments: [(Int, Int, Color, String)] = [
                (0,         introEnd,  Color(hex: "#1E1E1E"), "INTRO"),
                (introEnd,  drop1,     Color(hex: "#FF6500").opacity(0.25), "BUILD"),
                (drop1,     breakdown, Color(hex: "#FF6500").opacity(0.6),  "DROP"),
                (breakdown, drop2,     Color(hex: "#1A1A1A"), "BREAK"),
                (drop2,     outro,     Color(hex: "#FF6500").opacity(0.4),  "DROP 2"),
                (outro,     end,       Color(hex: "#141414"), "OUTRO"),
            ]

            for (s, e, color, label) in segments {
                let sx = xf(s); let ex = xf(e); let segW = ex - sx
                if segW < 1 { continue }
                ctx.fill(Path(CGRect(x: sx, y: 0, width: segW - 0.5, height: barH)),
                         with: .color(color))
                if segW > 28 {
                    let t = ctx.resolve(
                        Text(label)
                            .font(.system(size: 6, weight: .black, design: .monospaced))
                            .foregroundColor(Color(hex: "#606060"))
                    )
                    ctx.draw(t, at: CGPoint(x: sx + segW / 2, y: barH / 2), anchor: .center)
                }
            }

            // Transition markers + bar labels
            for bar in Set([introEnd, drop1, breakdown, outro]).filter({ $0 > 0 && $0 < end }) {
                let mx = xf(bar)
                var line = Path()
                line.move(to: CGPoint(x: mx, y: 0))
                line.addLine(to: CGPoint(x: mx, y: barH))
                ctx.stroke(line, with: .color(Color(hex: "#484848")), lineWidth: 0.5)

                let lbl = ctx.resolve(
                    Text("\(bar)")
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundColor(Color(hex: "#484848"))
                )
                ctx.draw(lbl, at: CGPoint(x: mx, y: size.height - 1), anchor: .bottom)
            }
        }
    }
}

// MARK: - Mix cues

private struct MixCuesSection: View {
    let intel: SongIntel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            songIntelLabel("MIX CUES")
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 9)

            MixCueRow(icon: "arrow.right.to.line",  label: "IN",  text: intel.mixInTip,  color: .cratesLive)
            Rectangle().fill(Color.cratesBorder.opacity(0.6)).frame(height: 1).padding(.horizontal, 12)
            MixCueRow(icon: "arrow.left.to.line",   label: "OUT", text: intel.mixOutTip, color: .cratesAccent)
            Rectangle().fill(Color.cratesBorder.opacity(0.6)).frame(height: 1).padding(.horizontal, 12)
            MixCueRow(icon: "slider.horizontal.3",  label: "EQ",  text: intel.eqTip,    color: .cratesDim)

            if intel.beforeBpmRange != nil || intel.afterBpmRange != nil {
                HStack(spacing: 10) {
                    if let before = intel.beforeBpmRange {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 7))
                            Text("PREV \(before)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.cratesGhost)
                    }
                    if let after = intel.afterBpmRange {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 7))
                            Text("NEXT \(after)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.cratesGhost)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 10)
            } else {
                Spacer().frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MixCueRow: View {
    let icon:  String
    let label: String
    let text:  String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8))
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(color)
            .frame(width: 38, alignment: .leading)

            Text(text)
                .font(.system(size: 9))
                .foregroundColor(Color(hex: "#606060"))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Key context

private struct KeyContextSection: View {
    let song: Song

    private var compatibleKeys: [(key: String, relation: String)] {
        guard let key = song.key,
              key.count >= 2,
              let num = Int(key.dropLast()),
              let letter = key.last
        else { return [] }

        let L = String(letter)
        let altL = L == "A" ? "B" : "A"
        let prev = num == 1 ? 12 : num - 1
        let next = num % 12 + 1

        return [
            (key: "\(prev)\(L)",   relation: "−1"),
            (key: key,             relation: "self"),
            (key: "\(num)\(altL)", relation: "rel"),
            (key: "\(next)\(L)",   relation: "+1"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                songIntelLabel("KEY COMPATIBILITY")
                Spacer()
                if let mk = song.musicalKey {
                    Text(mk)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.cratesKey.opacity(0.55))
                }
            }

            if compatibleKeys.isEmpty {
                Text("No key data")
                    .font(.system(size: 9))
                    .foregroundColor(.cratesGhost)
            } else {
                HStack(spacing: 5) {
                    ForEach(compatibleKeys, id: \.key) { item in
                        let isSelf = item.relation == "self"
                        VStack(spacing: 3) {
                            Text(item.key)
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(isSelf ? Color(hex: "#090909") : .cratesKey)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(isSelf ? Color.cratesKey : Color.cratesKey.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                            Text(item.relation)
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .foregroundColor(.cratesGhost)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Guide + Verdict

private struct GuideSection: View {
    let intel: SongIntel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Crowd tip
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.cratesAccent.opacity(0.55))
                    .padding(.top, 1)
                Text(intel.crowdTip)
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#656565"))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Color.cratesBorder.opacity(0.6)).frame(height: 1)

            // First-time guide
            songIntelLabel("FIRST TIME HEARING")
            Text(intel.firstTimeGuide)
                .font(.system(size: 9))
                .foregroundColor(Color(hex: "#575757"))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Color.cratesBorder.opacity(0.6)).frame(height: 1)

            // Verdict — amber highlight, highest visual weight
            songIntelLabel("VERDICT")
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.cratesAccent.opacity(0.5))
                    .frame(width: 2)
                Text(intel.verdict)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.cratesPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Loading animation (local, not reused from SetIntelView)

private struct SongScanBarsView: View {
    @State private var active = false
    private let heights: [CGFloat] = [5, 12, 8, 22, 6, 18, 28, 10, 20, 6, 16, 30, 8, 18, 5, 14]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(i))
                    .frame(width: 3, height: active ? heights[i] : heights[i] * 0.2)
                    .animation(
                        .easeInOut(duration: 0.3 + Double(i) * 0.025)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.035),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }

    private func barColor(_ i: Int) -> Color {
        let t = CGFloat(i) / CGFloat(heights.count)
        if t < 0.3  { return Color(hex: "#252525") }
        if t < 0.6  { return Color(hex: "#FF6500").opacity(0.35) }
        return Color(hex: "#FF6500")
    }
}

private struct SongScanPulse: View {
    @State private var scale = 1.0
    var body: some View {
        Circle()
            .fill(Color.cratesAccent)
            .frame(width: 5, height: 5)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    scale = 1.9
                }
            }
    }
}

// MARK: - Pairings (works well with)

private struct PairingsSection: View {
    let pairings: [SongPairing]

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "before": return .cratesKey
        case "after":  return Color(hex: "#FF3300")
        case "blend":  return .cratesAccent
        default:       return .cratesDim
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            songIntelLabel("WORKS WELL WITH")
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 9)

            ForEach(Array(pairings.enumerated()), id: \.offset) { i, pairing in
                if i > 0 {
                    Rectangle()
                        .fill(Color.cratesBorder.opacity(0.5))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                }
                HStack(alignment: .top, spacing: 8) {
                    // Type badge
                    Text(pairing.type.uppercased())
                        .font(.system(size: 6, weight: .black, design: .monospaced))
                        .tracking(0.3)
                        .foregroundColor(typeColor(pairing.type))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(typeColor(pairing.type).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .frame(width: 40, alignment: .leading)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 0) {
                            Text(pairing.title)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.cratesPrimary)
                                .lineLimit(1)
                            Text(" · ")
                                .font(.system(size: 8))
                                .foregroundColor(.cratesGhost)
                            Text(pairing.artist)
                                .font(.system(size: 8))
                                .foregroundColor(.cratesDim)
                                .lineLimit(1)
                        }
                        Text(pairing.reason)
                            .font(.system(size: 8))
                            .foregroundColor(Color(hex: "#505050"))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }

            Spacer().frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared section label

@ViewBuilder
private func songIntelLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 7, weight: .black, design: .monospaced))
        .tracking(2.5)
        .foregroundColor(Color(hex: "#2E2E2E"))
}
