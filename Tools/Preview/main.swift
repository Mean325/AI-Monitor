import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let useLiveData = arguments.contains("--live")
let useClaude = arguments.contains("--claude")
let useQoder = arguments.contains("--qoder")
let useGrok = arguments.contains("--grok")
let design = arguments
  .first(where: { $0.hasPrefix("--design=") })
  .flatMap { UsageCardDesign(rawValue: String($0.dropFirst("--design=".count))) }
  ?? .classic
let colorScheme = arguments
  .first(where: { $0.hasPrefix("--color=") })
  .flatMap { UsageCardColorScheme(rawValue: String($0.dropFirst("--color=".count))) }
  ?? .deepSpace
let activityState = arguments
  .first(where: { $0.hasPrefix("--activity=") })
  .flatMap { CodexActivityState(rawValue: String($0.dropFirst("--activity=".count))) }
  ?? .idle
let outputPath = arguments.first(where: { !$0.hasPrefix("--") }) ?? "./codex-linx-preview.jpg"

_ = NSApplication.shared

do {
  let rendered: RenderedUsageCard
  if useGrok {
    let snapshot = try GrokUsageClient().fetchSynchronously()
    print(
      "Grok remaining=\(snapshot.remainingPercent)% used=\(snapshot.usedPercent) plan=\(snapshot.planDisplayName) period=\(snapshot.periodType.rawValue) reset=\(snapshot.periodEnd?.description ?? "nil")"
    )
    rendered = try MainActor.assumeIsolated {
      try UsageCardRenderer.render(
        grokSnapshot: snapshot,
        activityState: activityState,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: colorScheme,
        design: design
      )
    }
  } else if useQoder {
    let snapshot = try QoderUsageClient().fetchSynchronously()
    let fetchedCreditSnapshot = try? QoderLogClient().fetchSynchronously()
    let creditSnapshot = fetchedCreditSnapshot?.hasData == true ? fetchedCreditSnapshot : nil
    print(
      "Qoder usage: todayPrompts=\(snapshot.todayPrompts), weekPrompts=\(snapshot.weekPrompts), sessions=\(snapshot.todaySessions), toolCalls=\(snapshot.todayToolCalls), lastActive=\(snapshot.lastActiveDate?.description ?? "nil")"
    )
    rendered = try MainActor.assumeIsolated {
      try UsageCardRenderer.render(
        qoderSnapshot: snapshot,
        creditSnapshot: creditSnapshot,
        activityState: activityState,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: colorScheme,
        design: design
      )
    }
  } else if useClaude {
    let snapshot = try ClaudeCodeUsageClient().fetchSynchronously()
    print(
      "Claude usage: today=\(snapshot.todayTokens), week=\(snapshot.weekTokens), sessions=\(snapshot.todaySessions), model=\(snapshot.model ?? "nil"), lastActive=\(snapshot.lastActiveDate?.description ?? "nil")"
    )
    rendered = try MainActor.assumeIsolated {
      try UsageCardRenderer.render(
        claudeSnapshot: snapshot,
        activityState: activityState,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: colorScheme,
        design: design
      )
    }
  } else {
    let snapshot = useLiveData ? try CodexRateLimitClient().fetchSynchronously() : .sample
    if useLiveData {
      let window = snapshot.windowMinutes.map(String.init) ?? "nil"
      let resetDate = snapshot.resetDate?.description ?? "nil"
      print(
        "Live usage: remaining=\(snapshot.remainingPercent), window=\(window), resets=\(snapshot.availableResetCount), resetDate=\(resetDate)"
      )
    }
    rendered = try MainActor.assumeIsolated {
      try UsageCardRenderer.render(
        snapshot: snapshot,
        activityState: activityState,
        safeAreaHeight: UsageCardLayout.defaultSafeArea,
        jpegQuality: 0.9,
        colorScheme: colorScheme,
        design: design
      )
    }
  }
  try rendered.data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
  let modeLabel = useGrok ? "grok" : (useQoder ? "qoder" : (useClaude ? "claude" : design.rawValue))
  print(
    "Rendered \(modeLabel)/\(colorScheme.rawValue)/\(activityState.rawValue) \(rendered.pixelWidth)x\(rendered.pixelHeight), \(rendered.data.count) bytes -> \(outputPath)"
  )
} catch {
  FileHandle.standardError.write(
    Data("Preview export failed: \(error.localizedDescription)\n".utf8))
  exit(1)
}
