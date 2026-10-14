import SwiftUI

struct MascotDialogView: View {
    var solarKw: Double = 0.0
    var chargeKw: Double = 0.0
    var dischargeKw: Double = 0.0
    var loadKw: Double = 0.0
    var gridExportKw: Double = 0.0
    var gridImportKw: Double = 0.0
    var socPct: Int = 80
    var todaySolarKwh: Double = 0.0
    var todayLoadKwh: Double = 0.0
    var todayChargeKwh: Double = 0.0
    var todayDischargeKwh: Double = 0.0
    var todayImportKwh: Double = 0.0
    var todayExportKwh: Double = 0.0
    var tomorrowSolarKwh: Double = 0.0
    var tomorrowLoadKwh: Double = 0.0
    var selfSufficiency: Double = 0.0
    var selfConsumption: Double = 0.0
    var historicalBills: [DailyBill] = []
    var weatherCondition: String = ""
    var temperature: String = ""
    var tariffInfo: String = ""
    var currentSkin: String = "slime"
    var apiKey: String = ""
    var onDismiss: () -> Void

    @StateObject private var aiManager = MascotAiManager.shared
    @State private var userInputText = ""
    @State private var isThinking = false

    private var hasApiKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Theme.bgDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    MascotView(
                        solarKw: solarKw,
                        chargeKw: chargeKw,
                        dischargeKw: dischargeKw,
                        loadKw: loadKw,
                        gridExportKw: gridExportKw,
                        gridImportKw: gridImportKw,
                        socPct: socPct,
                        weatherIcon: weatherCondition,
                        skin: currentSkin,
                        size: 38
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("WattPet AI Assistant 🐾")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)

                            Text(hasApiKey ? "Gemini 2.5" : "Local Engine")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(hasApiKey ? Theme.batteryGreen : Theme.solarGold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill((hasApiKey ? Theme.batteryGreen : Theme.solarGold).opacity(0.2))
                                )
                        }

                        Text(hasApiKey ? "Powered by Gemini 2.5 LLM" : "Standard Rule Engine")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.6))
                    }

                    Spacer()

                    // Clear History Button
                    Button(action: {
                        aiManager.clearHistory(hasApiKey: hasApiKey)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundColor(Color.white.opacity(0.6))
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }

                    // Close Dialog Button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.cardBg)

                Divider().background(Color.white.opacity(0.1))

                // Chat Messages List with Top Scrollable Prompt Chips
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Quick Prompt Chips (Top Item)
                            FlowLayout(spacing: 8) {
                                let chips = [
                                    "⚡ Live Power Analysis",
                                    "☀️ Solar generated yesterday?",
                                    "🔮 Tomorrow solar forecast?",
                                    "🔋 Battery Charging Strategy"
                                ]
                                ForEach(chips, id: \.self) { chipText in
                                    Button(action: {
                                        sendMessage(chipText)
                                    }) {
                                        Text(chipText)
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(red: 0.88, green: 0.91, blue: 0.94))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule().fill(Color(red: 0.2, green: 0.25, blue: 0.33))
                                            )
                                    }
                                }
                            }
                            .padding(.bottom, 6)

                            // Chat Messages
                            ForEach(aiManager.chatMessages) { msg in
                                ChatBubbleView(message: msg, skin: currentSkin)
                                    .id(msg.id)
                            }

                            if isThinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(Theme.solarGold)
                                        .scaleEffect(0.8)
                                    Text("WattPet is thinking...")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.white.opacity(0.6))
                                }
                                .padding(.leading, 36)
                                .id("thinking_indicator")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: aiManager.chatMessages.count) { _, _ in
                        if let lastMsg = aiManager.chatMessages.last {
                            withAnimation {
                                scrollProxy.scrollTo(lastMsg.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // Input Bar
                HStack(spacing: 10) {
                    TextField("Ask WattPet anything...", text: $userInputText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.08))
                        )
                        .onSubmit {
                            sendMessage(userInputText)
                        }

                    Button(action: {
                        sendMessage(userInputText)
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.black)
                            .padding(10)
                            .background(
                                Circle().fill(Theme.solarGold)
                            )
                    }
                    .disabled(userInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.cardBg)
            }
        }
        .onAppear {
            aiManager.initHistoryIfNeeded(hasApiKey: hasApiKey)
        }
    }

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && !isThinking else { return }

        let userMsg = MascotChatMessage(sender: "user", text: trimmed)
        aiManager.chatMessages.append(userMsg)
        userInputText = ""
        isThinking = true

        Task {
            let responseText = await aiManager.askMascot(
                userQuery: trimmed,
                solarKw: solarKw,
                chargeKw: chargeKw,
                dischargeKw: dischargeKw,
                loadKw: loadKw,
                gridExportKw: gridExportKw,
                gridImportKw: gridImportKw,
                socPct: socPct,
                todaySolarKwh: todaySolarKwh,
                todayLoadKwh: todayLoadKwh,
                todayChargeKwh: todayChargeKwh,
                todayDischargeKwh: todayDischargeKwh,
                todayImportKwh: todayImportKwh,
                todayExportKwh: todayExportKwh,
                tomorrowSolarKwh: tomorrowSolarKwh,
                tomorrowLoadKwh: tomorrowLoadKwh,
                selfSufficiency: selfSufficiency,
                selfConsumption: selfConsumption,
                historicalBills: historicalBills,
                forecastHours: FirebaseManager.shared.forecastHours,
                chargingPlan: FirebaseManager.shared.chargingPlan,
                chargingPlanHistory: FirebaseManager.shared.chargingPlanHistory,
                weatherCondition: weatherCondition,
                temperature: temperature,
                tariffInfo: tariffInfo,
                apiKey: apiKey
            )

            await MainActor.run {
                aiManager.chatMessages.append(MascotChatMessage(sender: "mascot", text: responseText))
                isThinking = false
            }
        }
    }
}

struct ChatBubbleView: View {
    let message: MascotChatMessage
    let skin: String

    private var isUser: Bool { message.sender == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                MascotView(skin: skin, size: 28)
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 13.5))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? Color(red: 0.25, green: 0.35, blue: 0.65) : Theme.cardBg)
                    )
            }

            if isUser {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Theme.solarGold)
            } else {
                Spacer(minLength: 40)
            }
        }
    }
}
