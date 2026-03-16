import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("General") {
                    Toggle("Enabled", isOn: $settings.enabled)
                    TextField("Wake Phrase", text: $settings.wakePhrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Active Hours") {
                    Stepper("Start: \(settings.activeHoursStart):00",
                            value: $settings.activeHoursStart, in: 0...23)
                    Stepper("End: \(settings.activeHoursEnd):00",
                            value: $settings.activeHoursEnd, in: 0...23)
                }

                Section("Rate Limits") {
                    Stepper("Max per hour: \(settings.maxInteractionsPerHour)",
                            value: $settings.maxInteractionsPerHour, in: 1...30)
                    Stepper("Cooldown: \(settings.cooldownSeconds)s",
                            value: $settings.cooldownSeconds, in: 10...300, step: 5)
                }

                Section("Character") {
                    Stepper("Max spoken seconds: \(settings.character.maxSpokenSeconds)",
                            value: $settings.character.maxSpokenSeconds, in: 5...30)
                    Toggle("Strict persona (third-person)", isOn: $settings.character.strictPersona)
                }

                Section("Protagonist Detection") {
                    Toggle("Require protagonist ready", isOn: $settings.protagonist.acceptWakeOnlyWhenReady)
                    Stepper("Preload window: \(settings.protagonist.preloadWindowSeconds)s",
                            value: $settings.protagonist.preloadWindowSeconds, in: 5...120, step: 5)
                    HStack {
                        Text("Min confidence")
                        Spacer()
                        Text(String(format: "%.2f", settings.protagonist.minConfidence))
                    }
                    Slider(value: $settings.protagonist.minConfidence, in: 0.1...0.9, step: 0.05)
                }

                Section("Safety") {
                    Toggle("Kids-only mode", isOn: $settings.contentPolicy.kidsOnly)
                    Toggle("Strict kid-safe", isOn: $settings.strictKidSafe)
                }

                Section("Blocked Topics") {
                    ForEach(settings.blockedTopics, id: \.self) { topic in
                        Text(topic)
                    }
                    .onDelete { indices in
                        settings.blockedTopics.remove(atOffsets: indices)
                    }
                }

                Section("Voice") {
                    Picker("TTS Voice", selection: $settings.voice) {
                        Text("Alloy").tag("alloy")
                        Text("Echo").tag("echo")
                        Text("Fable").tag("fable")
                        Text("Onyx").tag("onyx")
                        Text("Nova").tag("nova")
                        Text("Shimmer").tag("shimmer")
                    }
                }

                Section("Retries") {
                    Stepper("Pause retries: \(settings.retries.pause)",
                            value: $settings.retries.pause, in: 0...5)
                    Stepper("Generation retries: \(settings.retries.generation)",
                            value: $settings.retries.generation, in: 0...5)
                }

                Section("Telemetry") {
                    Toggle("Enabled", isOn: $settings.telemetry.enabled)
                }
            }
            .navigationTitle("Parent Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        settings.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
