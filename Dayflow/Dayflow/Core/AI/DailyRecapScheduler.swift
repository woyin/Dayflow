//
//  DailyRecapScheduler.swift
//  Dayflow
//

import Foundation

final class DailyRecapScheduler: @unchecked Sendable {
  static let shared = DailyRecapScheduler()

  private let queue = DispatchQueue(label: "com.dayflow.dailyRecapScheduler", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var isRunningCheck = false
  private let attemptBudget = DailyRecapAttemptBudget()

  private let checkInterval: TimeInterval = 5 * 60
  private let sourceLookbackWindowDays = 3

  private init() {}

  func start() {
    queue.async { [weak self] in
      self?.startOnQueue()
    }
  }

  func stop() {
    queue.async { [weak self] in
      self?.stopOnQueue()
    }
  }

  private func startOnQueue() {
    stopOnQueue()

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + checkInterval, repeating: checkInterval)
    timer.setEventHandler { [weak self] in
      self?.triggerCheckOnQueue(reason: "interval")
    }
    timer.resume()
    self.timer = timer

    triggerCheckOnQueue(reason: "startup")
  }

  private func stopOnQueue() {
    timer?.setEventHandler {}
    timer?.cancel()
    timer = nil
    // An in-flight check still owns this flag until its defer runs.
  }

  private func triggerCheckOnQueue(reason: String) {
    guard !isRunningCheck else {
      return
    }

    isRunningCheck = true
    Task.detached(priority: .utility) { [weak self] in
      await self?.runCheck(reason: reason)
    }
  }

  private func runCheck(reason: String) async {
    defer {
      queue.async { [weak self] in
        self?.isRunningCheck = false
      }
    }

    guard UserDefaults.standard.bool(forKey: "isDailyUnlocked") else {
      return
    }

    let now = Date()
    let hour = Calendar.current.component(.hour, from: now)

    guard hour >= 4 else {
      return
    }

    let currentDay = now.getDayInfoFor4AMBoundary()
    let targetDay = currentDay.dayString

    guard StorageManager.shared.fetchDailyStandup(forDay: targetDay) == nil else {
      return
    }

    let minimumActivityMinutes = 180
    guard
      let sourceDay = recapSourceDay(
        before: currentDay.startOfDay,
        targetDayString: targetDay,
        minimumActivityMinutes: minimumActivityMinutes
      )
    else {
      return
    }

    let sourceDayString = sourceDay.dayString
    let selectedProvider = DailyRecapGenerator.shared.selectedProvider()
    let providerAvailability =
      DailyRecapGenerator.shared.availabilitySnapshot()[selectedProvider]
      ?? DailyRecapProviderAvailability(
        isAvailable: true,
        detail: selectedProvider.pickerSubtitle
      )
    var providerProps: [String: Any] = [
      "daily_provider": selectedProvider.analyticsName,
      "daily_provider_label": selectedProvider.displayName,
      "daily_runtime": selectedProvider.runtimeLabel,
      "daily_model_or_tool": selectedProvider.modelOrTool as Any,
    ]

    guard selectedProvider.canGenerate else {
      AnalyticsService.shared.capture(
        "daily_auto_generation_check_skipped",
        providerProps.merging(
          [
            "trigger": reason,
            "target_day": targetDay,
            "source_day": sourceDayString,
            "reason": "no_provider_selected",
          ],
          uniquingKeysWith: { _, new in new }
        ))
      return
    }

    guard providerAvailability.isAvailable else {
      AnalyticsService.shared.capture(
        "daily_auto_generation_check_skipped",
        providerProps.merging(
          [
            "trigger": reason,
            "target_day": targetDay,
            "source_day": sourceDayString,
            "reason": "provider_unavailable",
            "provider_detail": providerAvailability.detail,
          ],
          uniquingKeysWith: { _, new in new }
        ))
      return
    }

    // Reserve before generation so failures and app restarts cannot restart the retry loop.
    guard let attempt = attemptBudget.reserveAttempt(forDay: targetDay) else {
      return
    }
    providerProps["attempt_number"] = attempt
    providerProps["max_attempts"] = DailyRecapAttemptBudget.maxAttempts

    let cards = StorageManager.shared.fetchTimelineCards(forDay: sourceDayString)
    let cardsText = DailyRecapGenerator.makeCardsText(day: sourceDayString, cards: cards)
    AnalyticsService.shared.capture(
      "daily_auto_generation_check_started",
      providerProps.merging(
        [
          "trigger": reason,
          "target_day": targetDay,
          "source_day": sourceDayString,
        ],
        uniquingKeysWith: { _, new in new }
      ))

    AnalyticsService.shared.capture(
      "daily_auto_generation_payload_built",
      providerProps.merging(
        [
          "trigger": reason,
          "target_day": targetDay,
          "source_day": sourceDayString,
          "input_mode": "cards_only",
          "cards_count": cards.count,
          "cards_text_chars": cardsText.count,
        ],
        uniquingKeysWith: { _, new in new }
      ))

    let startedAt = Date()
    do {
      let context = DailyRecapGenerationContext(
        targetDayString: targetDay,
        sourceDayString: sourceDayString,
        cards: cards,
        highlightsTitle: "Yesterday's highlights",
        tasksTitle: "Today's tasks",
        blockersTitle: "Blockers"
      )
      let draft = try await DailyRecapGenerator.shared.generate(context: context)
      guard let payloadJSON = draft.encodedJSONString() else {
        AnalyticsService.shared.capture(
          "daily_auto_generation_failed",
          providerProps.merging(
            [
              "trigger": reason,
              "target_day": targetDay,
              "source_day": sourceDayString,
              "failure_reason": "payload_encoding_failed",
            ],
            uniquingKeysWith: { _, new in new }
          ))
        return
      }

      StorageManager.shared.saveDailyStandup(forDay: targetDay, payloadJSON: payloadJSON)
      guard StorageManager.shared.fetchDailyStandup(forDay: targetDay) != nil else {
        AnalyticsService.shared.capture(
          "daily_auto_generation_failed",
          providerProps.merging(
            [
              "trigger": reason,
              "target_day": targetDay,
              "source_day": sourceDayString,
              "failure_reason": "db_save_verification_failed",
            ],
            uniquingKeysWith: { _, new in new }
          ))
        return
      }
      AnalyticsService.shared.capture(
        "daily_auto_generation_succeeded",
        providerProps.merging(
          [
            "trigger": reason,
            "target_day": targetDay,
            "source_day": sourceDayString,
            "latency_ms": Int(Date().timeIntervalSince(startedAt) * 1000),
            "highlights_count": draft.highlights.count,
            "tasks_count": draft.tasks.count,
            "unfinished_count": draft.tasks.count,
            "blockers_count": draft.blockersBody
              .split(whereSeparator: \.isNewline)
              .count,
          ],
          uniquingKeysWith: { _, new in new }
        ))

      await MainActor.run {
        NotificationService.shared.scheduleDailyRecapReadyNotification(forDay: targetDay)
      }
    } catch {
      let nsError = error as NSError
      AnalyticsService.shared.capture(
        "daily_auto_generation_failed",
        providerProps.merging(
          [
            "trigger": reason,
            "target_day": targetDay,
            "source_day": sourceDayString,
            "failure_reason": "api_error",
            "error_domain": nsError.domain,
            "error_code": nsError.code,
          ],
          uniquingKeysWith: { _, new in new }
        ))
    }
  }

  private func recapSourceDay(
    before targetStart: Date,
    targetDayString: String,
    minimumActivityMinutes: Int
  ) -> (dayString: String, startOfDay: Date, endOfDay: Date)? {
    let consumedSourceDays = DailyRecapSourceDayResolver.consumedSourceDays(
      from: StorageManager.shared.fetchAllDailyStandups(excludingDay: targetDayString)
    )
    guard
      let candidate = DailyRecapSourceDayResolver.sourceDay(
        before: targetStart,
        lookbackWindowDays: sourceLookbackWindowDays,
        consumedSourceDays: consumedSourceDays,
        hasMinimumActivity: { dayString in
          StorageManager.shared.hasMinimumTimelineActivity(
            forDay: dayString,
            minimumMinutes: minimumActivityMinutes
          )
        })
    else {
      return nil
    }

    return (
      dayString: candidate.dayString,
      startOfDay: candidate.startOfDay,
      endOfDay: candidate.endOfDay
    )
  }

  private static func makeCardsText(day: String, cards: [TimelineCard]) -> String {
    let ordered = cards.sorted { lhs, rhs in
      if lhs.startTimestamp == rhs.startTimestamp {
        return lhs.endTimestamp < rhs.endTimestamp
      }
      return lhs.startTimestamp < rhs.startTimestamp
    }

    guard !ordered.isEmpty else {
      return String(localized: "No timeline activities were recorded for \(day).")
    }

    var lines: [String] = ["Timeline activities for \(day):", ""]
    for (index, card) in ordered.enumerated() {
      let title = standupLine(from: card) ?? String(localized: "Untitled activity")
      let start = humanReadableClockTime(card.startTimestamp)
      let end = humanReadableClockTime(card.endTimestamp)
      lines.append("\(index + 1). \(start) - \(end): \(title)")

      let summary = card.summary.trimmingCharacters(in: .whitespacesAndNewlines)
      if !summary.isEmpty, summary != title {
        lines.append("   \(summary)")
      }
    }

    return lines.joined(separator: "\n")
  }

  private static func humanReadableClockTime(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let minuteOfDay = parseTimeHMMA(timeString: trimmed) else {
      return trimmed.lowercased()
    }

    let hour24 = (minuteOfDay / 60) % 24
    let minute = minuteOfDay % 60
    let meridiem = hour24 >= 12 ? "pm" : "am"
    let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
    return String(format: "%d:%02d%@", hour12, minute, meridiem)
  }

  private static func standupLine(from card: TimelineCard) -> String? {
    let trimmedTitle = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedTitle.isEmpty {
      return trimmedTitle
    }

    let trimmedSummary = card.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedSummary.isEmpty ? nil : trimmedSummary
  }
}
