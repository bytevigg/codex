import SwiftUI

struct PlayerView: View {
    @Environment(AppSettings.self) private var settings
    @StateObject private var orchestrator = SessionOrchestrator(settings: .load())
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // YouTube player area
                YouTubeWebView(bridge: orchestrator.youtube)
                    .ignoresSafeArea(.container, edges: .horizontal)

                // Status bar
                statusBar
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)

                // Last reply bubble
                if let reply = orchestrator.lastReply {
                    replyBubble(reply)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: orchestrator.lastReply)
            .navigationTitle("YouTube Buddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    listeningIndicator
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(settings)
            }
            .task {
                await orchestrator.startListening()
            }
            .onDisappear {
                orchestrator.stopListening()
            }
        }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        HStack {
            stateIcon
            Text(orchestrator.statusMessage ?? stateLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch orchestrator.state {
        case .idle:
            Image(systemName: "mic.fill")
                .foregroundStyle(.green)
                .symbolEffect(.pulse, isActive: orchestrator.wakeListener.isListening)
        case .triggered, .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
        case .capturing:
            Image(systemName: "ear.fill")
                .foregroundStyle(.blue)
        case .responding:
            Image(systemName: "bubble.left.fill")
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)
        case .resuming:
            Image(systemName: "play.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var stateLabel: String {
        switch orchestrator.state {
        case .idle: return "Listening..."
        case .triggered: return "Wake phrase detected!"
        case .paused: return "Video paused"
        case .capturing: return "Listening to you..."
        case .responding: return "Thinking..."
        case .resuming: return "Resuming video..."
        }
    }

    @ViewBuilder
    private var listeningIndicator: some View {
        if orchestrator.wakeListener.isListening {
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Live")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    private func replyBubble(_ text: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("YouTube Buddy")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.body)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            Spacer()
        }
    }
}
