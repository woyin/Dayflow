//
//  OnboardingPrototypeFlow.swift
//  Dayflow
//

import SwiftUI

enum OnboardingPrototypeStep: Int, CaseIterable, Identifiable {
  case preferences
  case chooseProvider
  case placeholder

  var id: Int { rawValue }

  var analyticsName: String {
    switch self {
    case .preferences:
      return "preferences"
    case .chooseProvider:
      return "choose_provider"
    case .placeholder:
      return "placeholder"
    }
  }

  var screenName: String {
    "onboarding_\(analyticsName)"
  }

  var next: OnboardingPrototypeStep? {
    OnboardingPrototypeStep(rawValue: rawValue + 1)
  }
}

struct OnboardingPrototypeFlow: View {
  private let flowVariant: String
  private let entryPoint: String

  @State private var currentStep: OnboardingPrototypeStep
  @State private var flowID = UUID().uuidString.lowercased()
  @State private var hasTrackedStart = false
  @State private var hasTrackedCompletion = false

  init(
    initialStep: OnboardingPrototypeStep = .preferences,
    flowVariant: String = "prototype_v1",
    entryPoint: String = "preview"
  ) {
    _currentStep = State(initialValue: initialStep)
    self.flowVariant = flowVariant
    self.entryPoint = entryPoint
  }

  var body: some View {
    ZStack {
      Color(red: 0.12, green: 0.12, blue: 0.12)
        .ignoresSafeArea()

      switch currentStep {
      case .preferences:
        OnboardingPrototypePreferencesStep(
          onContinue: { hasPaidAI in
            OnboardingPrototypeAnalytics.trackStepCompleted(
              step: .preferences,
              flowID: flowID,
              flowVariant: flowVariant,
              advanceMethod: hasPaidAI ? "yes_button" : "no_button",
              extraProps: ["has_paid_ai": hasPaidAI]
            )
            if let nextStep = OnboardingPrototypeStep.preferences.next {
              currentStep = nextStep
            }
          }
        )

      case .chooseProvider:
        OnboardingPrototypeChooseProviderStep(
          onSelect: { provider in
            OnboardingPrototypeAnalytics.trackStepCompleted(
              step: .chooseProvider,
              flowID: flowID,
              flowVariant: flowVariant,
              advanceMethod: "select_button",
              extraProps: ["selected_provider": provider]
            )
            if let nextStep = OnboardingPrototypeStep.chooseProvider.next {
              currentStep = nextStep
            }
          }
        )

      case .placeholder:
        OnboardingPrototypePlaceholderStep(
          onFinish: {
            advance(from: .placeholder, method: "finish_button")
          }
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      OnboardingBackdrop()
    }
    .preferredColorScheme(.light)
    .onAppear {
      guard !hasTrackedStart else { return }
      hasTrackedStart = true
      OnboardingPrototypeAnalytics.trackFlowStarted(
        flowID: flowID,
        flowVariant: flowVariant,
        entryPoint: entryPoint,
        stepCount: OnboardingPrototypeStep.allCases.count
      )
      trackStepViewed(currentStep)
    }
    .onChange(of: currentStep) { oldStep, newStep in
      guard oldStep != newStep else { return }
      trackStepViewed(newStep)
    }
  }

  private func trackStepViewed(_ step: OnboardingPrototypeStep) {
    OnboardingPrototypeAnalytics.trackStepViewed(
      step: step,
      flowID: flowID,
      flowVariant: flowVariant
    )
  }

  private func advance(from step: OnboardingPrototypeStep, method: String) {
    OnboardingPrototypeAnalytics.trackStepCompleted(
      step: step,
      flowID: flowID,
      flowVariant: flowVariant,
      advanceMethod: method
    )

    if let nextStep = step.next {
      currentStep = nextStep
      return
    }

    guard !hasTrackedCompletion else { return }
    hasTrackedCompletion = true
    OnboardingPrototypeAnalytics.trackFlowCompleted(
      flowID: flowID,
      flowVariant: flowVariant,
      stepCount: OnboardingPrototypeStep.allCases.count
    )
  }
}

// MARK: - Placeholder Step

private struct OnboardingPrototypePlaceholderStep: View {
  let onFinish: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      VStack(spacing: 10) {
        Text("Prototype checkpoint")
          .font(.custom("InstrumentSerif-Regular", size: 44))
          .foregroundColor(.black.opacity(0.9))

        Text(
          "The preferences screen is now wired up. We can keep replacing the remaining placeholders step by step without touching production onboarding yet."
        )
        .font(.custom("Figtree", size: 17))
        .foregroundColor(.black.opacity(0.65))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
      }

      HStack(spacing: 16) {
        DayflowSurfaceButton(
          action: onFinish,
          content: {
            Text("Finish prototype")
              .font(.custom("Figtree", size: 15))
              .fontWeight(.semibold)
          },
          background: Color(hex: "FF9F6F"),
          foreground: .white,
          borderColor: Color(hex: "F4C8B1"),
          cornerRadius: 200,
          horizontalPadding: 28,
          verticalPadding: 14,
          minWidth: 170,
          showOverlayStroke: false,
          innerGlowColor: Color(hex: "FFDCCB").opacity(0.9)
        )
      }
    }
    .padding(.horizontal, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

enum OnboardingPrototypeAnalytics {
  private static let isPreviewRuntime =
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

  static func trackFlowStarted(
    flowID: String,
    flowVariant: String,
    entryPoint: String,
    stepCount: Int
  ) {
    capture(
      "onboarding_started",
      [
        "flow_id": flowID,
        "flow_variant": flowVariant,
        "entry_point": entryPoint,
        "step_count": stepCount,
      ]
    )
  }

  static func trackStepViewed(
    step: OnboardingPrototypeStep,
    flowID: String,
    flowVariant: String
  ) {
    let props = stepProps(step: step, flowID: flowID, flowVariant: flowVariant)
    screen(step.screenName, props)
    capture("onboarding_step_viewed", props)
  }

  static func trackStepCompleted(
    step: OnboardingPrototypeStep,
    flowID: String,
    flowVariant: String,
    advanceMethod: String,
    extraProps: [String: Any] = [:]
  ) {
    var props = stepProps(step: step, flowID: flowID, flowVariant: flowVariant)
    props["advance_method"] = advanceMethod
    extraProps.forEach { props[$0.key] = $0.value }
    capture("onboarding_step_completed", props)
  }

  static func trackFlowCompleted(
    flowID: String,
    flowVariant: String,
    stepCount: Int
  ) {
    capture(
      "onboarding_completed",
      [
        "flow_id": flowID,
        "flow_variant": flowVariant,
        "step_count": stepCount,
      ]
    )
  }

  private static func stepProps(
    step: OnboardingPrototypeStep,
    flowID: String,
    flowVariant: String
  ) -> [String: Any] {
    [
      "flow_id": flowID,
      "flow_variant": flowVariant,
      "step": step.analyticsName,
      "step_index": step.rawValue + 1,
      "step_count": OnboardingPrototypeStep.allCases.count,
    ]
  }

  private static func capture(_ name: String, _ props: [String: Any]) {
    guard !isPreviewRuntime else { return }
    AnalyticsService.shared.capture(name, props)
  }

  private static func screen(_ name: String, _ props: [String: Any]) {
    guard !isPreviewRuntime else { return }
    AnalyticsService.shared.screen(name, props)
  }
}

#Preview("Onboarding Prototype") {
  OnboardingPrototypeFlow()
    .frame(
      width: 900, height: 600
    )
}

#Preview("Onboarding Prototype Preferences") {
  OnboardingPrototypeFlow(initialStep: .preferences)
    .frame(width: 1200, height: 800)
}

#Preview("Onboarding Prototype Choose Provider") {
  OnboardingPrototypeFlow(initialStep: .chooseProvider)
    .frame(width: 1200, height: 800)
}

#Preview("Onboarding Prototype Placeholder") {
  OnboardingPrototypeFlow(initialStep: .placeholder)
    .frame(width: 600, height: 400)
}
