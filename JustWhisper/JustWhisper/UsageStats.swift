//
//  UsageStats.swift
//  JustWhisper
//
//  Created by Scott Soifer on 2/7/26.
//

import Foundation

/// Tracks usage statistics for JustWhisper, persisted via UserDefaults
class UsageStats: ObservableObject {
    static let shared = UsageStats()

    private let defaults = UserDefaults.standard

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let totalWords = "Stats_TotalWords"
        static let totalRecordingSeconds = "Stats_TotalRecordingSeconds"
        static let totalTranscriptions = "Stats_TotalTranscriptions"
        static let firstUsedDate = "Stats_FirstUsedDate"
        static let longestRecordingSeconds = "Stats_LongestRecordingSeconds"
    }

    // MARK: - Published Properties
    @Published var totalWords: Int
    @Published var totalRecordingSeconds: Double
    @Published var totalTranscriptions: Int
    @Published var firstUsedDate: Date?
    @Published var longestRecordingSeconds: Double

    private init() {
        totalWords = defaults.integer(forKey: Keys.totalWords)
        totalRecordingSeconds = defaults.double(forKey: Keys.totalRecordingSeconds)
        totalTranscriptions = defaults.integer(forKey: Keys.totalTranscriptions)
        longestRecordingSeconds = defaults.double(forKey: Keys.longestRecordingSeconds)

        let storedDate = defaults.double(forKey: Keys.firstUsedDate)
        if storedDate > 0 {
            firstUsedDate = Date(timeIntervalSince1970: storedDate)
        } else {
            firstUsedDate = nil
        }
    }

    // MARK: - Recording a transcription

    /// Call this after a successful transcription to update stats
    func recordTranscription(text: String, recordingDurationSeconds: Double) {
        // Set first used date if not set
        if firstUsedDate == nil {
            firstUsedDate = Date()
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.firstUsedDate)
        }

        // Count words
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        totalWords += wordCount
        defaults.set(totalWords, forKey: Keys.totalWords)

        // Recording duration
        totalRecordingSeconds += recordingDurationSeconds
        defaults.set(totalRecordingSeconds, forKey: Keys.totalRecordingSeconds)

        // Transcription count
        totalTranscriptions += 1
        defaults.set(totalTranscriptions, forKey: Keys.totalTranscriptions)

        // Longest recording
        if recordingDurationSeconds > longestRecordingSeconds {
            longestRecordingSeconds = recordingDurationSeconds
            defaults.set(longestRecordingSeconds, forKey: Keys.longestRecordingSeconds)
        }
    }

    // MARK: - Derived Stats

    var totalRecordingMinutes: Double {
        totalRecordingSeconds / 60.0
    }

    var averageWordsPerTranscription: Double {
        guard totalTranscriptions > 0 else { return 0 }
        return Double(totalWords) / Double(totalTranscriptions)
    }

    var wordsPerMinute: Double {
        guard totalRecordingMinutes > 0 else { return 0 }
        return Double(totalWords) / totalRecordingMinutes
    }

    var daysSinceFirstUse: Int? {
        guard let firstUsed = firstUsedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: firstUsed, to: Date()).day
    }

    // MARK: - Reset

    func resetStats() {
        totalWords = 0
        totalRecordingSeconds = 0
        totalTranscriptions = 0
        longestRecordingSeconds = 0
        firstUsedDate = nil

        defaults.removeObject(forKey: Keys.totalWords)
        defaults.removeObject(forKey: Keys.totalRecordingSeconds)
        defaults.removeObject(forKey: Keys.totalTranscriptions)
        defaults.removeObject(forKey: Keys.firstUsedDate)
        defaults.removeObject(forKey: Keys.longestRecordingSeconds)
    }
}
