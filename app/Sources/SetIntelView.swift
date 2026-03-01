import SwiftUI

// MARK: - Data model

struct SetIntel: Codable {
    struct VenueContext: Codable {
        let venueType: String
        let timeSlot:  String
        let crowdType: String
        let duration:  String
        let verdict:   String
    }

    struct TrackIntel: Codable {
        let toPosition:    Int      // 1-based incoming track number
        let title:         String
        let note:          String
        let hasKeyWarning: Bool
    }

    let venue:               VenueContext
    let bpmValues:           [Int]      // one per track, 0 = unknown
    let energyValues:        [Double]   // one per track, 0.0 = unknown
    let keyPath:             [String]   // Camelot key per track
    let transitions:         [TrackIntel]
    let peakTrack:           Int?       // 1-based
    let keyWarningPositions: Set<Int>
}

// MARK: - Service

enum SetIntelService {

    static func analyse(crate: Crate) async -> SetIntel? {
        guard let claudePath = BPMService.findClaude() else { return nil }

        let tracklist = crate.songs.enumerated().map { i, s -> String in
            var line = "\(i + 1). \"\(s.title)\" by \(s.artist)"
            if let b = s.bpm    { line += " [BPM: \(b)]" }
            if let k = s.key    { line += " [Key: \(k)]" }
            if let e = s.energy { line += " [Energy: \(String(format: "%.1f", e))/10]" }
            return line
        }.joined(separator: "\n")

        let count = crate.songs.count
        let name  = crate.name

        let prompt = """
        You are an expert DJ set analyst with deep knowledge of DJ craft, crowd psychology and music theory.
        Search the web to identify these tracks and give accurate metadata.

        SET: "\(name)"
        TRACKS:
        \(tracklist)

        Return ONLY a single raw JSON object — no markdown, no explanation:
        {
          "venue_type": "<best venue fit: warehouse / rooftop / intimate club / festival main stage / beach>",
          "time_slot": "<e.g. 2am peak / warm-up / closing set / sunset>",
          "crowd_type": "<e.g. afro house faithful / mixed crowd / deep house heads>",
          "duration_estimate": "<total estimated set duration, e.g. 1h 24m>",
          "verdict": "<2 sentences: overall assessment of this set's strengths and any weaknesses>",
          "peak_track": <1-based track number where energy peaks, integer>,
          "bpm_values": [<bpm as integer per track in order, use 0 if unknown>],
          "energy_values": [<energy 0.0-10.0 float per track in order, use 0.0 if unknown>],
          "key_path": ["<camelot key string per track in order, e.g. \"8A\", use null if unknown>"],
          "transitions": [
            {
              "from": <1-based from-track integer>,
              "to": <1-based to-track integer>,
              "note": "<specific actionable tip for this transition, max 55 chars>",
              "key_warning": <true if keys clash, false otherwise>
            }
          ]
        }
        """

        let songs = crate.songs
        return await Task.detached(priority: .utility) {
            guard let output = claudeShell(claudePath, args: [
                "--output-format", "text",
                "--dangerously-skip-permissions",
                "-p", prompt,
            ]) else { return nil }
            return parseIntel(output: output, songs: songs, count: count)
        }.value
    }

    // MARK: Parsing

    private static func parseIntel(output: String, songs: [Song], count: Int) -> SetIntel? {
        guard let start = output.firstIndex(of: "{"),
              let end   = output.lastIndex(of: "}"),
              let data  = String(output[start...end]).data(using: .utf8),
              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        func str(_ k: String) -> String { (obj[k] as? String) ?? "—" }

        let bpmRaw   = obj["bpm_values"]    as? [Any] ?? []
        let ergRaw   = obj["energy_values"] as? [Any] ?? []
        let keyRaw   = obj["key_path"]      as? [Any] ?? []
        let transRaw = obj["transitions"]   as? [[String: Any]] ?? []

        var bpmValues: [Int] = bpmRaw.map {
            if let n = $0 as? Int    { return n }
            if let d = $0 as? Double { return Int(d) }
            return 0
        }
        var energyValues: [Double] = ergRaw.map {
            if let d = $0 as? Double { return d }
            if let i = $0 as? Int   { return Double(i) }
            return 0.0
        }
        var keyPath: [String] = keyRaw.map { v -> String in
            guard let s = v as? String, !s.isEmpty, s.lowercased() != "null" else { return "?" }
            return s
        }

        // Pad to song count
        while bpmValues.count    < count { bpmValues.append(0) }
        while energyValues.count < count { energyValues.append(0.0) }
        while keyPath.count      < count { keyPath.append("?") }

        // Merge with existing song metadata where Claude returned nothing
        for (i, song) in songs.enumerated() where i < count {
            if bpmValues[i] == 0,    let b = song.bpm    { bpmValues[i] = b }
            if energyValues[i] == 0, let e = song.energy { energyValues[i] = e }
            if keyPath[i] == "?",    let k = song.key    { keyPath[i] = k }
        }

        var keyWarningSet = Set<Int>()
        let transitions: [SetIntel.TrackIntel] = transRaw.compactMap { t in
            guard let to = t["to"] as? Int else { return nil }
            let note = t["note"] as? String ?? ""
            let warn = t["key_warning"] as? Bool ?? false
            if warn { keyWarningSet.insert(to) }
            return SetIntel.TrackIntel(
                toPosition:    to,
                title:         to <= songs.count ? songs[to - 1].title : "Track \(to)",
                note:          note,
                hasKeyWarning: warn
            )
        }

        return SetIntel(
            venue: SetIntel.VenueContext(
                venueType: str("venue_type"),
                timeSlot:  str("time_slot"),
                crowdType: str("crowd_type"),
                duration:  str("duration_estimate"),
                verdict:   str("verdict")
            ),
            bpmValues:           bpmValues,
            energyValues:        energyValues,
            keyPath:             keyPath,
            transitions:         transitions,
            peakTrack:           obj["peak_track"] as? Int,
            keyWarningPositions: keyWarningSet
        )
    }

    // MARK: Shell

    private static func claudeShell(_ path: String, args: [String]) -> String? {
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

// MARK: - Camelot compatibility

private func camelotCompatible(_ a: String, _ b: String) -> Bool {
    guard a != "?", b != "?" else { return false }
    guard let na = Int(a.dropLast()), let nb = Int(b.dropLast()) else { return false }
    let la = String(a.last ?? "?"); let lb = String(b.last ?? "?")
    if na == nb { return true }                              // same number
    if la == lb { let d = abs(na - nb); return d == 1 || d == 11 } // adjacent same letter
    return false
}

// MARK: - Main panel view

struct SetIntelView: View {
    let crate: Crate

    @EnvironmentObject var crateState: CrateState

    enum LoadState { case idle, loading, done, failed }

    @State private var loadState: LoadState = .idle
    @State private var intel:     SetIntel? = nil
    @State private var pulseScale = 1.0

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Rectangle().fill(Color.cratesBorder).frame(height: 1)
            panelBody
        }
        .background(Color.cratesBg)
        .onAppear {
            // Restore cached result instantly — no re-analysis needed
            if intel == nil, let cached = crateState.setIntelCache[crate.id] {
                intel     = cached
                loadState = .done
            }
        }
    }

    // MARK: Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(loadState == .loading ? Color.cratesAccent : Color.cratesKey)
                .frame(width: 5, height: 5)
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        pulseScale = loadState == .loading ? 1.8 : 1.0
                    }
                }
                .onChange(of: loadState == LoadState.loading) { isLoading in
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        pulseScale = isLoading ? 1.8 : 1.0
                    }
                }

            Text("SET INTEL")
                .font(.system(size: 10, weight: .black))
                .tracking(2.5)
                .foregroundColor(.cratesPrimary)

            Spacer()

            if loadState != .loading {
                Button { Task { await runAnalysis() } } label: {
                    if loadState == .done {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.cratesDim)
                            .frame(width: 22, height: 22)
                            .background(Color.cratesElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Text(loadState == .failed ? "RETRY" : "ANALYSE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(Color.cratesBg)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.cratesAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .buttonStyle(.plain)
                .help(loadState == .done ? "Re-analyse set" : "")
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Body switching on state

    @ViewBuilder
    private var panelBody: some View {
        switch loadState {
        case .idle:    idlePromptView
        case .loading: loadingView
        case .done:
            if let intel {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        IntelVenueSection(venue: intel.venue)
                        sectionDivider
                        IntelEnergySection(
                            energyValues: intel.energyValues,
                            bpmValues:    intel.bpmValues,
                            peakTrack:    intel.peakTrack
                        )
                        sectionDivider
                        IntelKeyFlowSection(keyPath: intel.keyPath)
                        sectionDivider
                        IntelTransitionsSection(transitions: intel.transitions)
                        Spacer().frame(height: 24)
                    }
                }
            }
        case .failed:  failedView
        }
    }

    private var sectionDivider: some View {
        Rectangle().fill(Color.cratesBorder).frame(height: 1)
    }

    // MARK: Idle / loading / failed states

    private var idlePromptView: some View {
        VStack(spacing: 18) {
            // Decorative signal bars
            HStack(alignment: .bottom, spacing: 3) {
                ForEach([6, 11, 8, 18, 6, 24, 10, 20, 7, 16, 9, 22, 6], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.cratesGhost)
                        .frame(width: 3, height: CGFloat(h))
                }
            }
            VStack(spacing: 6) {
                Text("CLAUDE READS THE SET")
                    .font(.system(size: 9, weight: .black))
                    .tracking(2)
                    .foregroundColor(.cratesDim)
                Text("Searches the web · maps energy flow\nkey compatibility · crowd fit")
                    .font(.system(size: 10))
                    .foregroundColor(.cratesGhost)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 22) {
            ScanBarsView()
                .frame(width: 260, height: 44)
            VStack(spacing: 5) {
                Text("CLAUDE IS READING THE SET…")
                    .font(.system(size: 9, weight: .black))
                    .tracking(2)
                    .foregroundColor(.cratesAccent)
                Text("searching web · analysing \(crate.songs.count) tracks")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.cratesDim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundColor(.cratesAccent.opacity(0.4))
            Text("ANALYSIS FAILED")
                .font(.system(size: 9, weight: .black))
                .tracking(2)
                .foregroundColor(.cratesDim)
            Text("Check that Claude CLI is installed\nand authenticated.")
                .font(.system(size: 10))
                .foregroundColor(.cratesGhost)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Analysis trigger

    @MainActor
    private func runAnalysis() async {
        loadState = .loading
        if let result = await SetIntelService.analyse(crate: crate) {
            intel     = result
            loadState = .done
            crateState.cacheSetIntel(result, for: crate.id)
        } else {
            loadState = .failed
        }
    }
}

// MARK: - Venue section

private struct IntelVenueSection: View {
    let venue: SetIntel.VenueContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            intelLabel("VENUE FIT")

            // Metadata chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach([venue.venueType, venue.timeSlot, venue.crowdType], id: \.self) { tag in
                        Text(tag.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.cratesAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.cratesAccent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.cratesAccent.opacity(0.25), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer()
                    Text(venue.duration)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.cratesDim)
                }
            }

            // Verdict text
            Text(venue.verdict)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#686868"))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Energy + BPM section

private struct IntelEnergySection: View {
    let energyValues: [Double]
    let bpmValues:    [Int]
    let peakTrack:    Int?

    private var bpmRange: String {
        let known = bpmValues.filter { $0 > 0 }
        guard let lo = known.min(), let hi = known.max() else { return "—" }
        return lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                intelLabel("ENERGY ARC")
                Spacer()
                if let peak = peakTrack {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7))
                        Text("PEAK AT \(peak)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(.cratesAccent.opacity(0.8))
                }
            }

            EnergyArcChart(energyValues: energyValues, peakTrack: peakTrack)
                .frame(height: 64)

            HStack {
                intelLabel("BPM CURVE")
                Spacer()
                Text(bpmRange)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.cratesDim)
            }

            BPMCurveChart(bpmValues: bpmValues)
                .frame(height: 36)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Key flow section

private struct IntelKeyFlowSection: View {
    let keyPath: [String]

    private var clashCount: Int {
        guard keyPath.count > 1 else { return 0 }
        return zip(keyPath, keyPath.dropFirst()).filter { !camelotCompatible($0, $1) && $0 != "?" && $1 != "?" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                intelLabel("KEY FLOW")
                Spacer()
                if clashCount > 0 {
                    Text("\(clashCount) CLASH\(clashCount > 1 ? "ES" : "")")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.cratesAccent.opacity(0.7))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(keyPath.enumerated()), id: \.offset) { i, key in
                        let compatible = i == 0 ? true : camelotCompatible(keyPath[i - 1], key)
                        KeyChip(key: key, isCompatible: compatible)

                        if i < keyPath.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7))
                                .foregroundColor(.cratesGhost)
                        }
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KeyChip: View {
    let key:          String
    let isCompatible: Bool

    private var chipColor: Color {
        if key == "?" { return Color.cratesGhost }
        return isCompatible ? Color.cratesKey : Color.cratesAccent
    }

    var body: some View {
        Text(key)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundColor(chipColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(chipColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(chipColor.opacity(0.35), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - Transitions section

private struct IntelTransitionsSection: View {
    let transitions: [SetIntel.TrackIntel]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                intelLabel("TRANSITIONS")
                Spacer()
                let clashes = transitions.filter { $0.hasKeyWarning }.count
                if clashes > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7))
                        Text("\(clashes) KEY CLASH\(clashes > 1 ? "ES" : "")")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                    }
                    .foregroundColor(.cratesAccent.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if transitions.isEmpty {
                Text("No transition data returned.")
                    .font(.system(size: 10))
                    .foregroundColor(.cratesGhost)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                ForEach(Array(transitions.enumerated()), id: \.offset) { i, t in
                    TransitionRow(intel: t, isLast: i == transitions.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TransitionRow: View {
    let intel:  SetIntel.TrackIntel
    let isLast: Bool
    @State private var hovered = false

    private var accentColor: Color {
        intel.hasKeyWarning ? .cratesAccent : .cratesKey
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Key clash stripe
                Rectangle()
                    .fill(intel.hasKeyWarning ? Color.cratesAccent : Color.clear)
                    .frame(width: 2)

                HStack(spacing: 8) {
                    Text(String(format: "%02d", intel.toPosition))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(intel.hasKeyWarning ? .cratesAccent : .cratesDim)
                        .frame(width: 22, alignment: .trailing)

                    if intel.hasKeyWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.cratesAccent.opacity(0.7))
                    }

                    Text(intel.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.cratesPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, intel.note.isEmpty ? 9 : 3)
            }
            .background(hovered ? Color.cratesSurface : Color.clear)

            if !intel.note.isEmpty {
                HStack(spacing: 0) {
                    Rectangle().fill(intel.hasKeyWarning ? Color.cratesAccent : Color.clear).frame(width: 2)
                    Text(intel.note)
                        .font(.system(size: 9).italic())
                        .foregroundColor(intel.hasKeyWarning ? Color.cratesAccent.opacity(0.65) : Color.cratesDim)
                        .padding(.leading, 44)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(hovered ? Color.cratesSurface : Color.clear)
            }

            if !isLast {
                Rectangle()
                    .fill(Color.cratesBorder)
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
        .onHover { hovered = $0 }
    }
}

// MARK: - Energy arc chart (Canvas)

private struct EnergyArcChart: View {
    let energyValues: [Double]
    let peakTrack:    Int?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let count = energyValues.count
            guard count > 1 else { return }

            let maxE = energyValues.max() ?? 10
            let minE = energyValues.min() ?? 0
            let range = max(maxE - minE, 1.5)
            let pad: CGFloat = 6

            func point(at i: Int) -> CGPoint {
                let x = CGFloat(i) / CGFloat(count - 1) * w
                let y = h - pad - ((CGFloat(energyValues[i]) - CGFloat(minE)) / CGFloat(range)) * (h - pad * 2)
                return CGPoint(x: x, y: y)
            }

            let pts = (0..<count).map { point(at: $0) }

            // Fill below curve
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: h))
            for p in pts { fill.addLine(to: p) }
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(hex: "#FF6500").opacity(0.28), location: 0),
                    .init(color: Color(hex: "#FF6500").opacity(0),    location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint:   CGPoint(x: 0, y: h)
            ))

            // Track tick marks at bottom
            for i in 0..<count {
                let x = CGFloat(i) / CGFloat(count - 1) * w
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: h - 1))
                tick.addLine(to: CGPoint(x: x, y: h - 4))
                ctx.stroke(tick, with: .color(Color(hex: "#222222")), lineWidth: 1)
            }

            // Main arc line
            var line = Path()
            line.move(to: pts[0])
            for p in pts.dropFirst() { line.addLine(to: p) }
            ctx.stroke(line, with: .color(Color(hex: "#FF6500")),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Peak dot
            if let peak = peakTrack, peak >= 1, peak <= count {
                let pt = pts[peak - 1]
                let dot = Path(ellipseIn: CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7))
                ctx.fill(dot, with: .color(Color(hex: "#FF6500")))
                // Halo
                let halo = Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
                ctx.stroke(halo, with: .color(Color(hex: "#FF6500").opacity(0.3)), lineWidth: 1)
            }

            // Track number labels: first, mid, last
            let labelIndices = [0, count / 2, count - 1]
            for i in labelIndices {
                let x = CGFloat(i) / CGFloat(count - 1) * w
                let label = "\(i + 1)"
                let resolved = ctx.resolve(Text(label)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(Color(hex: "#3A3A3A")))
                ctx.draw(resolved, at: CGPoint(x: x, y: h + 2), anchor: .top)
            }
        }
    }
}

// MARK: - BPM curve chart (Canvas)

private struct BPMCurveChart: View {
    let bpmValues: [Int]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let count = bpmValues.count
            let known = bpmValues.filter { $0 > 0 }
            guard known.count > 1 else { return }

            let minBPM = CGFloat(known.min()!) - 2
            let maxBPM = CGFloat(known.max()!) + 2
            let range  = max(maxBPM - minBPM, 4)

            func point(at i: Int) -> CGPoint? {
                let bpm = bpmValues[i]
                guard bpm > 0 else { return nil }
                let x = CGFloat(i) / CGFloat(count - 1) * w
                let y = h - 4 - ((CGFloat(bpm) - minBPM) / range) * (h - 8)
                return CGPoint(x: x, y: y)
            }

            // Horizontal guide at midpoint
            let midY = h / 2
            var guide = Path()
            guide.move(to: CGPoint(x: 0, y: midY))
            guide.addLine(to: CGPoint(x: w, y: midY))
            ctx.stroke(guide, with: .color(Color(hex: "#1E1E1E")),
                       style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))

            // Connect known BPM points
            var line = Path()
            var started = false
            for i in 0..<count {
                if let p = point(at: i) {
                    if !started { line.move(to: p); started = true }
                    else        { line.addLine(to: p) }
                }
            }
            ctx.stroke(line, with: .color(Color(hex: "#5A5A5A")),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))

            // Dots + first/last BPM labels
            let knownIndices = bpmValues.indices.filter { bpmValues[$0] > 0 }
            for i in knownIndices {
                if let p = point(at: i) {
                    let dot = Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
                    ctx.fill(dot, with: .color(Color(hex: "#5A5A5A")))
                }
            }
            if let fi = knownIndices.first, let fp = point(at: fi) {
                let label = ctx.resolve(Text("\(bpmValues[fi])")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#5A5A5A")))
                ctx.draw(label, at: CGPoint(x: fp.x + 8, y: fp.y), anchor: .leading)
            }
            if let li = knownIndices.last, knownIndices.count > 1, let lp = point(at: li) {
                let label = ctx.resolve(Text("\(bpmValues[li])")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#5A5A5A")))
                ctx.draw(label, at: CGPoint(x: lp.x - 8, y: lp.y), anchor: .trailing)
            }
        }
    }
}

// MARK: - Scanning animation

private struct ScanBarsView: View {
    @State private var active = false

    private let heights: [CGFloat] = [6, 14, 10, 28, 8, 20, 32, 12, 24, 8, 18, 36, 10, 22, 6, 16]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(i))
                    .frame(width: 3, height: active ? heights[i] : heights[i] * 0.25)
                    .animation(
                        .easeInOut(duration: 0.35 + Double(i) * 0.03)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.04),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }

    private func barColor(_ i: Int) -> Color {
        let t = CGFloat(i) / CGFloat(heights.count)
        if t < 0.35 { return Color(hex: "#2A2A2A") }
        if t < 0.65 { return Color(hex: "#FF6500").opacity(0.4) }
        return Color(hex: "#FF6500")
    }
}

// MARK: - Shared label helper

@ViewBuilder
fileprivate func intelLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 8, weight: .black))
        .tracking(2.5)
        .foregroundColor(Color(hex: "#2E2E2E"))
}
