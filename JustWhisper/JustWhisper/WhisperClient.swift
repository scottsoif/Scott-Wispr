//
//  WhisperClient.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import Foundation
import os.log

/// Logger for Whisper operations
private let logger = Logger(subsystem: "com.mycompany.justWhisper", category: "WhisperClient")

/// Whisper provider options
enum WhisperProvider: String, CaseIterable {
    case azure = "azure"
    case openai = "openai"
    
    var displayName: String {
        switch self {
        case .azure: return "Azure Whisper"
        case .openai: return "OpenAI Whisper"
        }
    }
}

/// Log entry for UI display``
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel
    
    enum LogLevel {
        case info, warning, error
        
        var emoji: String {
            switch self {
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
}

/// Client for handling audio transcription via multiple Whisper providers
class WhisperClient: ObservableObject {
    private let session = URLSession.shared
    
    /// Published logs for UI display
    @Published var logs: [LogEntry] = []
    
    /// Maximum number of log entries to keep
    private let maxLogEntries = 100
    
    /// Adds a log entry to the published logs array
    @MainActor
    internal func addLog(_ message: String, level: LogEntry.LogLevel) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        logs.append(entry)
        
        // Keep only the most recent entries
        if logs.count > maxLogEntries {
            logs.removeFirst(logs.count - maxLogEntries)
        }
        
        // Also log to system logger
        switch level {
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        }
    }
    
    /// Clears all log entries
    @MainActor
    func clearLogs() {
        logs.removeAll()
    }
    
    /// Transcribes audio data using the configured Whisper provider
    /// - Parameter audioData: PCM audio data to transcribe
    /// - Returns: Transcribed text
    func transcribe(audioData: Data) async throws -> String {
        await addLog("Starting transcription...", level: .info)
        
        // Get provider preference
        let providerString = UserDefaults.standard.string(forKey: "WhisperProvider") ?? "azure"
        let provider = WhisperProvider(rawValue: providerString) ?? .azure
        
        await addLog("Using \(provider.displayName) for transcription", level: .info)
        
        switch provider {
        case .azure:
            return try await transcribeWithAzure(audioData: audioData)
        case .openai:
            return try await transcribeWithOpenAI(audioData: audioData)
        }
    }
    
    /// Transcribes audio data using Azure Whisper API
    private func transcribeWithAzure(audioData: Data) async throws -> String {
        // Azure Whisper configuration - get from UserDefaults (user preferences)
        let apiKey = UserDefaults.standard.string(forKey: "AzureWhisperAPIKey") ?? ""
        let deployment = UserDefaults.standard.string(forKey: "AzureWhisperDeployment") ?? "whisper"
        let apiVersion = UserDefaults.standard.string(forKey: "AzureWhisperAPIVersion") ?? "2024-08-01-preview"
        let endpoint = UserDefaults.standard.string(forKey: "AzureWhisperEndpoint") ?? ""
        
        await addLog("Using Azure Whisper configuration from user preferences", level: .info)
        
        guard !apiKey.isEmpty else {
            await addLog("Missing Azure API key - please configure in settings", level: .error)
            throw WhisperError.missingAPIKey
        }
        
        guard !endpoint.isEmpty else {
            await addLog("Missing Azure endpoint URL - please configure in settings", level: .error)
            throw WhisperError.invalidURL
        }
        
        guard !deployment.isEmpty else {
            await addLog("Missing Azure deployment name - please configure in settings", level: .error)
            throw WhisperError.invalidURL
        }
        
        // Construct Azure endpoint URL
        let fullEndpoint = "\(endpoint)openai/deployments/\(deployment)/audio/transcriptions?api-version=\(apiVersion)"
        
        await addLog("Using Azure endpoint: \(fullEndpoint)", level: .info)
        
        do {
            // Convert PCM data to WAV format
            await addLog("Converting audio to WAV format...", level: .info)
            let wavData = try convertPCMToWAV(audioData)
            await addLog("Audio converted successfully, WAV size: \(wavData.count) bytes, original PCM size: \(audioData.count) bytes", level: .info)
            
            // Validate audio duration (should be at least 0.1 seconds)
            let estimatedDuration = Double(audioData.count) / (44100.0 * 4.0) // 4 bytes per sample at 44.1kHz (32-bit float input)
            await addLog("Estimated audio duration: \(String(format: "%.2f", estimatedDuration)) seconds", level: .info)
            
            if estimatedDuration < 0.1 {
                await addLog("Audio too short, may cause transcription issues", level: .warning)
            }
            
            // Log audio format details
            await addLog("Audio format: 44.1kHz, 16-bit PCM, mono", level: .info)
            
            // Create multipart form request
            await addLog("Creating Azure API request...", level: .info)
            let request = try createAzureTranscriptionRequest(
                endpoint: fullEndpoint,
                apiKey: apiKey,
                audioData: wavData
            )
            
            // Send request
            await addLog("Sending request to Azure Whisper API...", level: .info)
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await addLog("Invalid response type", level: .error)
                throw WhisperError.invalidResponse
            }
            
            await addLog("Received response with status code: \(httpResponse.statusCode)", level: .info)
            
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = "HTTP error: \(httpResponse.statusCode)"
                await addLog(errorMessage, level: .error)
                
                // Try to get error details from response
                if let errorData = String(data: data, encoding: .utf8) {
                    await addLog("Error details: \(errorData)", level: .error)
                }
                
                throw WhisperError.httpError(httpResponse.statusCode)
            }
            
            // Parse response
            await addLog("Parsing transcription response...", level: .info)
            
            do {
                let transcriptionResponse = try JSONDecoder().decode(
                    WhisperResponse.self,
                    from: data
                )
                
                let transcribedText = transcriptionResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
                await addLog("Raw transcription result: '\(transcribedText)'", level: .info)
                await addLog("Transcription length: \(transcribedText.count) characters", level: .info)
                
                // Log additional response details if available
                if let language = transcriptionResponse.language {
                    await addLog("Detected language: \(language)", level: .info)
                }
                if let duration = transcriptionResponse.duration {
                    await addLog("Audio duration: \(duration) seconds", level: .info)
                }
                
                // Log segment analysis for debugging
                // if let segments = transcriptionResponse.segments {
                //     await addLog("Found \(segments.count) segments", level: .info)
                //     for (index, segment) in segments.enumerated() {
                //         if let noSpeechProb = segment.no_speech_prob {
                //             let speechQuality = noSpeechProb < 0.5 ? "Good" : "Poor"
                //             await addLog("Segment \(index): no_speech_prob=\(String(format: "%.3f", noSpeechProb)) (\(speechQuality))", level: .info)
                //         }
                //         if let avgLogprob = segment.avg_logprob {
                //             let confidence = avgLogprob > -1.0 ? "High" : "Low"
                //             await addLog("Segment \(index): avg_logprob=\(String(format: "%.3f", avgLogprob)) (\(confidence))", level: .info)
                //         }
                //     }
                // }
                
                // Check for common transcription issues
                if transcribedText.lowercased() == "you" {
                    await addLog("⚠️ Detected 'you' response - this may indicate audio quality or API configuration issues", level: .warning)
                    await addLog("💡 Suggestion: Check microphone levels, reduce background noise, or try recording closer to the microphone", level: .info)
                }
                
                if transcribedText.isEmpty {
                    await addLog("⚠️ Empty transcription result - checking response structure", level: .warning)
                    
                    // Try to extract text from segments if main text is empty
                    if let segments = transcriptionResponse.segments, !segments.isEmpty {
                        let segmentTexts = segments.compactMap { $0.text }.joined(separator: " ")
                        if !segmentTexts.isEmpty {
                            await addLog("Found text in segments: '\(segmentTexts)'", level: .info)
                            return segmentTexts.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                
                await addLog("Transcription completed successfully", level: .info)
                return transcribedText
                
            } catch {
                await addLog("JSON decode error: \(error.localizedDescription)", level: .error)
                
                // Try to parse as a simpler structure or different format
                if let responseString = String(data: data, encoding: .utf8) {
                    await addLog("Attempting to extract text from raw response...", level: .info)
                    
                    // Maybe the response is just plain text?
                    if !responseString.isEmpty && !responseString.contains("{") && !responseString.contains("}") {
                        await addLog("Response appears to be plain text: '\(responseString)'", level: .info)
                        return responseString.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    // Try to extract text field manually
                    if let textRange = responseString.range(of: "\"text\"\\s*:\\s*\"([^\"]*)", options: .regularExpression) {
                        let textValue = String(responseString[textRange])
                        if let match = textValue.range(of: "\"([^\"]*)", options: .regularExpression) {
                            let extractedText = String(textValue[match]).replacingOccurrences(of: "\"", with: "")
                            await addLog("Manually extracted text: '\(extractedText)'", level: .info)
                            return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                
                throw error
            }
            
        } catch {
            await addLog("Azure transcription failed: \(error.localizedDescription)", level: .error)
            throw error
        }
    }
    
    /// Transcribes audio data using OpenAI Whisper API
    private func transcribeWithOpenAI(audioData: Data) async throws -> String {
        // OpenAI Whisper configuration - get from UserDefaults (user preferences)
        let apiKey = UserDefaults.standard.string(forKey: "OpenAIWhisperAPIKey") ?? ""
        let model = UserDefaults.standard.string(forKey: "OpenAIWhisperModel") ?? "whisper-1"
        let baseURL = UserDefaults.standard.string(forKey: "OpenAIWhisperBaseURL") ?? "https://api.openai.com/v1"
        
        await addLog("Using OpenAI Whisper configuration from user preferences", level: .info)
        
        guard !apiKey.isEmpty else {
            await addLog("Missing OpenAI API key - please configure in settings", level: .error)
            throw WhisperError.missingAPIKey
        }
        
        // Construct OpenAI endpoint URL
        let fullEndpoint = "\(baseURL)/audio/transcriptions"
        
        await addLog("Using OpenAI endpoint: \(fullEndpoint)", level: .info)
        await addLog("Using model: \(model)", level: .info)
        
        do {
            // Convert PCM data to WAV format
            await addLog("Converting audio to WAV format...", level: .info)
            let wavData = try convertPCMToWAV(audioData)
            await addLog("Audio converted successfully, WAV size: \(wavData.count) bytes, original PCM size: \(audioData.count) bytes", level: .info)
            
            // Validate audio duration (should be at least 0.1 seconds)
            let estimatedDuration = Double(audioData.count) / (44100.0 * 4.0) // 4 bytes per sample at 44.1kHz (32-bit float input)
            await addLog("Estimated audio duration: \(String(format: "%.2f", estimatedDuration)) seconds", level: .info)
            
            if estimatedDuration < 0.1 {
                await addLog("Audio too short, may cause transcription issues", level: .warning)
            }
            
            // Log audio format details
            await addLog("Audio format: 44.1kHz, 16-bit PCM, mono", level: .info)
            
            // Create multipart form request
            await addLog("Creating OpenAI API request...", level: .info)
            let request = try createOpenAITranscriptionRequest(
                endpoint: fullEndpoint,
                apiKey: apiKey,
                model: model,
                audioData: wavData
            )
            
            // Send request
            await addLog("Sending request to OpenAI Whisper API...", level: .info)
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await addLog("Invalid response type", level: .error)
                throw WhisperError.invalidResponse
            }
            
            await addLog("Received response with status code: \(httpResponse.statusCode)", level: .info)
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = "HTTP error: \(httpResponse.statusCode)"
                await addLog(errorMessage, level: .error)
                
                // Try to get error details from response
                if let errorData = String(data: data, encoding: .utf8) {
                    await addLog("Error details: \(errorData)", level: .error)
                }
                
                throw WhisperError.httpError(httpResponse.statusCode)
            }
            
            // Parse response
            await addLog("Parsing transcription response...", level: .info)
            
            do {
                let transcriptionResponse = try JSONDecoder().decode(
                    WhisperResponse.self,
                    from: data
                )
                
                let transcribedText = transcriptionResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
                await addLog("Raw transcription result: '\(transcribedText)'", level: .info)
                await addLog("Transcription length: \(transcribedText.count) characters", level: .info)
                
                // Log additional response details if available
                if let language = transcriptionResponse.language {
                    await addLog("Detected language: \(language)", level: .info)
                }
                if let duration = transcriptionResponse.duration {
                    await addLog("Audio duration: \(duration) seconds", level: .info)
                }
                
                // Check for common transcription issues
                if transcribedText.lowercased() == "you" {
                    await addLog("⚠️ Detected 'you' response - this may indicate audio quality or API configuration issues", level: .warning)
                    await addLog("💡 Suggestion: Check microphone levels, reduce background noise, or try recording closer to the microphone", level: .info)
                }
                
                if transcribedText.isEmpty {
                    await addLog("⚠️ Empty transcription result - checking response structure", level: .warning)
                    
                    // Try to extract text from segments if main text is empty
                    if let segments = transcriptionResponse.segments, !segments.isEmpty {
                        let segmentTexts = segments.compactMap { $0.text }.joined(separator: " ")
                        if !segmentTexts.isEmpty {
                            await addLog("Found text in segments: '\(segmentTexts)'", level: .info)
                            return segmentTexts.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                
                await addLog("OpenAI transcription completed successfully", level: .info)
                return transcribedText
                
            } catch {
                await addLog("JSON decode error: \(error.localizedDescription)", level: .error)
                
                // Try to parse as a simpler structure or different format
                if let responseString = String(data: data, encoding: .utf8) {
                    await addLog("Attempting to extract text from raw response...", level: .info)
                    
                    // Maybe the response is just plain text?
                    if !responseString.isEmpty && !responseString.contains("{") && !responseString.contains("}") {
                        await addLog("Response appears to be plain text: '\(responseString)'", level: .info)
                        return responseString.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    // Try to extract text field manually
                    if let textRange = responseString.range(of: "\"text\"\\s*:\\s*\"([^\"]*)", options: .regularExpression) {
                        let textValue = String(responseString[textRange])
                        if let match = textValue.range(of: "\"([^\"]*)", options: .regularExpression) {
                            let extractedText = String(textValue[match]).replacingOccurrences(of: "\"", with: "")
                            await addLog("Manually extracted text: '\(extractedText)'", level: .info)
                            return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                
                throw error
            }
            
        } catch {
            await addLog("OpenAI transcription failed: \(error.localizedDescription)", level: .error)
            throw error
        }
    }
    
    /// Extract API key for use by other components
    func extractAPIKey() -> String? {
        // Get API key based on current provider
        let providerString = UserDefaults.standard.string(forKey: "WhisperProvider") ?? "azure"
        let provider = WhisperProvider(rawValue: providerString) ?? .azure
        
        switch provider {
        case .azure:
            return UserDefaults.standard.string(forKey: "AzureWhisperAPIKey")
        case .openai:
            return UserDefaults.standard.string(forKey: "OpenAIWhisperAPIKey")
        }
    }
    
    /// Converts PCM data to WAV format for API compatibility
    private func convertPCMToWAV(_ pcmData: Data) throws -> Data {
        let sampleRate: UInt32 = 44100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16  // Changed to 16-bit for better compatibility
        let bytesPerSample = bitsPerSample / 8
        let frameSize = channels * bytesPerSample
        
        // Validate input data size
        guard pcmData.count > 0 else {
            throw WhisperError.audioConversionError
        }
        
        // Convert 32-bit float PCM to 16-bit PCM
        let convertedPCMData = convertFloatPCMTo16Bit(pcmData)
        
        var wavData = Data()
        
        // WAV header
        wavData.append("RIFF".data(using: .ascii)!) // ChunkID
        
        let fileSize = UInt32(36 + convertedPCMData.count)
        withUnsafeBytes(of: fileSize.littleEndian) { wavData.append(Data($0)) }
        
        wavData.append("WAVE".data(using: .ascii)!) // Format
        wavData.append("fmt ".data(using: .ascii)!) // Subchunk1ID
        
        let subchunk1Size: UInt32 = 16
        withUnsafeBytes(of: subchunk1Size.littleEndian) { wavData.append(Data($0)) }
        
        let audioFormat: UInt16 = 1 // PCM format instead of IEEE float
        withUnsafeBytes(of: audioFormat.littleEndian) { wavData.append(Data($0)) }
        
        withUnsafeBytes(of: channels.littleEndian) { wavData.append(Data($0)) }
        withUnsafeBytes(of: sampleRate.littleEndian) { wavData.append(Data($0)) }
        
        let byteRate = sampleRate * UInt32(frameSize)
        withUnsafeBytes(of: byteRate.littleEndian) { wavData.append(Data($0)) }
        
        withUnsafeBytes(of: frameSize.littleEndian) { wavData.append(Data($0)) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { wavData.append(Data($0)) }
        
        wavData.append("data".data(using: .ascii)!) // Subchunk2ID
        
        let dataSize = UInt32(convertedPCMData.count)
        withUnsafeBytes(of: dataSize.littleEndian) { wavData.append(Data($0)) }
        
        // Audio data
        wavData.append(convertedPCMData)
        
        return wavData
    }
    
    /// Converts 32-bit float PCM data to 16-bit PCM data
    private func convertFloatPCMTo16Bit(_ floatData: Data) -> Data {
        var int16Data = Data()
        
        // Process data in 4-byte chunks (32-bit floats)
        let floatCount = floatData.count / 4
        floatData.withUnsafeBytes { buffer in
            let floatBuffer = buffer.bindMemory(to: Float32.self)
            for i in 0..<floatCount {
                let floatSample = floatBuffer[i]
                // Clamp to [-1.0, 1.0] and convert to 16-bit
                let clampedSample = max(-1.0, min(1.0, floatSample))
                let int16Sample = Int16(clampedSample * 32767.0)
                withUnsafeBytes(of: int16Sample.littleEndian) { bytes in
                    int16Data.append(Data(bytes))
                }
            }
        }
        
        return int16Data
    }
    
    /// Creates a multipart form request for the Azure Whisper API
    private func createAzureTranscriptionRequest(
        endpoint: String,
        apiKey: String,
        audioData: Data
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw WhisperError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Set headers for Azure
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        
        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        
        // Create multipart body
        var body = Data()
        
        // Response format - try verbose_json to get more details
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Language (helps with accuracy)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        
        // Temperature for more focused results - using 0.0 for most deterministic output
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
        body.append("0.0\r\n".data(using: .utf8)!)
        
        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        return request
    }
    
    /// Creates a multipart form request for the OpenAI Whisper API
    private func createOpenAITranscriptionRequest(
        endpoint: String,
        apiKey: String,
        model: String,
        audioData: Data
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw WhisperError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Set headers for OpenAI
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        
        // Create multipart body
        var body = Data()
        
        // Model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)
        
        // Response format - try verbose_json to get more details
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Language (helps with accuracy)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        
        // Temperature for more focused results - using 0.0 for most deterministic output
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
        body.append("0.0\r\n".data(using: .utf8)!)
        
        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        return request
    }
}

// MARK: - Response Models

/// Response model for Whisper API transcription
struct WhisperResponse: Codable {
    let text: String
    
    // Azure OpenAI might return additional fields
    let task: String?
    let language: String?
    let duration: Double?
    let segments: [WhisperSegment]?
    
    // Handle potential nested structure
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        task = try container.decodeIfPresent(String.self, forKey: .task)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        segments = try container.decodeIfPresent([WhisperSegment].self, forKey: .segments)
    }
    
    private enum CodingKeys: String, CodingKey {
        case text, task, language, duration, segments
    }
}

/// Segment information from Whisper response
struct WhisperSegment: Codable {
    let id: Int?
    let seek: Double?
    let start: Double?
    let end: Double?
    let text: String?
    let tokens: [Int]?
    let temperature: Double?
    let avg_logprob: Double?
    let compression_ratio: Double?
    let no_speech_prob: Double?
}

// MARK: - Error Types

/// Errors that can occur during Whisper API interaction
enum WhisperError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case audioConversionError
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Whisper API key is required"
        case .invalidURL:
            return "Invalid Whisper endpoint URL"
        case .invalidResponse:
            return "Invalid response from Whisper API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .audioConversionError:
            return "Failed to convert audio data"
        }
    }
}

// MARK: - Test Implementation

/// Dummy Whisper client for testing and development
class DummyWhisperClient: WhisperClient {
    private let cannedResponses = [
        "Hello, this is a test transcription.",
        "The quick brown fox jumps over the lazy dog.",
        "This is another sample response for testing.",
        "Um, this response contains some filler words, you know.",
        "New line. This has multiple sentences. Actually, this is the corrected version.",
        "Testing microphone input with clear speech.",
        "Voice recognition is working properly.",
        "Dictating text for the JustWhisper application.",
        "This is a longer response to test how the system handles multiple words and phrases in a single transcription result.",
        "Short test."
    ]
    
    override func transcribe(audioData: Data) async throws -> String {
        await addLog("Starting dummy transcription...", level: .info)
        await addLog("Audio data size: \(audioData.count) bytes", level: .info)
        
        // Estimate audio duration
        let estimatedDuration = Double(audioData.count) / (44100.0 * 4.0)
        await addLog("Estimated audio duration: \(String(format: "%.2f", estimatedDuration)) seconds", level: .info)
        
        // Simulate network delay
        await addLog("Simulating API call delay...", level: .info)
        try await Task.sleep(nanoseconds: UInt64.random(in: 500_000_000...2_000_000_000)) // 0.5-2 seconds
        
        // Return random canned response, weighted by audio length
        let response: String
        if audioData.count < 1000 {
            // Short audio - return short response
            response = ["Short test.", "Yes.", "Hello.", "Testing."].randomElement() ?? "Test"
        } else {
            // Normal audio - return varied response
            response = cannedResponses.randomElement() ?? "Test transcription"
        }
        
        await addLog("Dummy transcription completed: '\(response)'", level: .info)
        await addLog("Response length: \(response.count) characters", level: .info)
        
        return response
    }
}
