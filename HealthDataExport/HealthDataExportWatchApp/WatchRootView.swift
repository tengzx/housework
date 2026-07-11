import SwiftUI

/// The watch app's home. Opens straight into the shortcut-based time tracker
/// (its in-progress screen when a session is running). Shortcut and workout
/// lists stay one tap away via the symmetric toolbar icons.
struct WatchRootView: View {
    @StateObject private var auth = WatchAuthSync.shared
    @StateObject private var activeWorkout = WatchActiveWorkoutStore.shared

    var body: some View {
        Group {
            if let ref = activeWorkout.current {
                // Show the workout full-screen by swapping the root (no system close
                // button — the workout is ended via the swipe-in controls page).
                WatchActiveWorkoutView(
                    sessionId: ref.sessionId,
                    name: ref.name,
                    playsStartCountdown: ref.playsStartCountdown
                )
                    .transition(.move(edge: .bottom))
            } else {
                home
            }
        }
        // Request HealthKit access once at launch so the permission prompt is
        // handled up front, not when the user starts their first workout.
        .task { await WatchWorkoutManager.requestAuthorization() }
        // Prefetch templates so the fitness icon shows the list instantly.
        .task { await WatchTemplateStore.shared.load() }
        .task {
            auth.activate()
        }
    }

    private var home: some View {
        NavigationStack {
            WatchTimeTrackerView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            WatchTimeTrackerView(displayMode: .shortcutListOnly)
                        } label: {
                            Image(systemName: "bolt.fill")
                        }
                        .accessibilityLabel("快捷指令")
                    }

                    // Replaces the top-right clock with a shortcut into the
                    // workout template list.
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            WatchTemplateListView()
                        } label: {
                            Image(systemName: "figure.strengthtraining.traditional")
                        }
                        .accessibilityLabel("运动")
                    }
                }
        }
    }
}
