//
//  TranscriptCleaner.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import Foundation

/// Handles post-processing of raw transcripts with text cleaning and command replacement
class TranscriptCleaner {
    
    private let fillerWords = [
        "um", "uh", "ah", "er", "like", "you know", "sort of", "kind of",
        "basically", "actually", "literally", "so", "well", "right",
        "okay", "alright", "hmm", "yeah", "yes", "yep", "mhm"
    ]
    
    // Configuration options
    struct CleanerOptions {
        var removeFillerWords: Bool = true
        var processPunctuationCommands: Bool = true
        var processLineBreakCommands: Bool = true
        var processFormattingCommands: Bool = true
        var applySelfCorrection: Bool = true
        var automaticCapitalization: Bool = true
        var applyWordReplacements: Bool = true
        var useIntelligentWordReplacements: Bool = true
    }
    
    // Default options
    private var options: CleanerOptions
    
    // Word replacement dictionary - loaded from UserDefaults
    private var wordReplacements: [String: String] = [:]
    
    init(options: CleanerOptions = CleanerOptions()) {
        self.options = options
        loadWordReplacements()
    }
    
    // Update options
    func updateOptions(_ newOptions: CleanerOptions) {
        self.options = newOptions
    }
    
    // Get current options
    func getOptions() -> CleanerOptions {
        return self.options
    }
    
    /// Cleans and processes raw transcript text
    /// - Parameter raw: Raw transcript from speech recognition
    /// - Returns: Cleaned and processed text ready for output
    func cleanTranscript(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Apply cleaning steps in order
        if options.applyWordReplacements {
            text = applyWordReplacements(text)
        }
        if options.removeFillerWords {
            text = stripFillerWords(text)
        }
        if options.processFormattingCommands {
            text = processCommands(text)
        }
        if options.applySelfCorrection {
            text = applySelfCorrection(text)
        }
        text = cleanupSentences(text)
        
        // Strip surrounding quotes if present (in case the transcript was quoted)
        text = stripSurroundingQuotes(text)
        
        return text
    }
    
    /// Async version that supports intelligent word replacements using GPT
    /// - Parameter raw: Raw transcript from speech recognition
    /// - Returns: Cleaned and processed text ready for output
    func cleanTranscriptAsync(_ raw: String) async throws -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Apply word replacements (intelligent if enabled and configured)
        if options.applyWordReplacements {
            if options.useIntelligentWordReplacements {
                do {
                    text = try await applyIntelligentWordReplacements(text)
                } catch {
                    print("Failed to apply intelligent word replacements, falling back to basic: \(error)")
                    text = applyWordReplacements(text)
                }
            } else {
                text = applyWordReplacements(text)
            }
        }
        
        if options.removeFillerWords {
            text = stripFillerWords(text)
        }
        if options.processFormattingCommands {
            text = processCommands(text)
        }
        if options.applySelfCorrection {
            text = applySelfCorrection(text)
        }
        text = cleanupSentences(text)
        
        // Strip surrounding quotes if present (in case the transcript was quoted)
        text = stripSurroundingQuotes(text)
        
        return text
    }
    
    /// Removes filler words using word boundaries
    private func stripFillerWords(_ text: String) -> String {
        var result = text
        
        for fillerWord in fillerWords {
            // Create regex pattern for word boundaries (case-insensitive)
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fillerWord))\\b"
            
            do {
                let regex = try NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                )
                
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: ""
                )
            } catch {
                print("Failed to create regex for filler word: \(fillerWord)")
            }
        }
        
        return result
    }
    
    /// Processes voice commands and replaces them with appropriate text
    private func processCommands(_ text: String) -> String {
        var result = text
        
        // Build command patterns based on enabled options
        var commandPatterns: [(pattern: String, replacement: String)] = []
        
        // Line break commands
        if options.processLineBreakCommands {
            let lineBreakCommands: [(pattern: String, replacement: String)] = [
                // New line commands
                ("\\b(new line|newline)\\b", "\n"),
                
                // Bullet point commands
                ("\\b(bullet point|bullet|dash)\\b", "\n• "),
                
                // Paragraph break
                ("\\b(new paragraph|paragraph)\\b", "\n\n"),
                
                // Tab
                ("\\btab\\b", "\t")
            ]
            commandPatterns.append(contentsOf: lineBreakCommands)
        }
        
        // Punctuation commands
        if options.processPunctuationCommands {
            let punctuationCommands: [(pattern: String, replacement: String)] = [
                // Common punctuation
                ("\\bperiod\\b", "."),
                ("\\bcomma\\b", ","),
                ("\\bquestion mark\\b", "?"),
                ("\\bexclamation point\\b", "!"),
                ("\\bcolon\\b", ":"),
                ("\\bsemicolon\\b", ";")
            ]
            commandPatterns.append(contentsOf: punctuationCommands)
        }
        
        // Formatting commands
        if options.processFormattingCommands {
            let formattingCommands: [(pattern: String, replacement: String)] = [
                // Quote handling - extract content between "quote" and "end quote"
                ("\\bquote\\s+(.+?)\\s+end\\s+quote\\b", "$1"),
                
                // Capitalization commands
                ("\\bcap\\s+(\\w)", "$1"), // "cap next" -> capitalize next word
                ("\\ball caps\\s+(.+?)\\s+end caps\\b", "$1") // all caps handling
            ]
            commandPatterns.append(contentsOf: formattingCommands)
        }
        
        for (pattern, replacement) in commandPatterns {
            do {
                let regex = try NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                )
                
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: replacement
                )
            } catch {
                print("Failed to create regex for pattern: \(pattern)")
            }
        }
        
        // Handle "all caps" sections
        result = processAllCapsCommands(result)
        
        return result
    }
    
    /// Processes "all caps" commands by converting text to uppercase
    private func processAllCapsCommands(_ text: String) -> String {
        let pattern = "\\ball caps\\s+(.+?)\\s+end caps\\b"
        
        do {
            let regex = try NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
            
            let matches = regex.matches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: text.utf16.count)
            )
            
            var result = text
            
            // Process matches in reverse order to maintain string indices
            for match in matches.reversed() {
                guard match.numberOfRanges > 1 else { continue }
                
                let fullRange = match.range(at: 0)
                let contentRange = match.range(at: 1)
                
                if let fullNSRange = Range(fullRange, in: text),
                   let contentNSRange = Range(contentRange, in: text) {
                    let uppercaseContent = String(text[contentNSRange]).uppercased()
                    result.replaceSubrange(fullNSRange, with: uppercaseContent)
                }
            }
            
            return result
        } catch {
            print("Failed to process all caps commands: \(error)")
            return text
        }
    }
    
    /// Applies self-correction rules to handle "Actually" patterns
    private func applySelfCorrection(_ text: String) -> String {
        // Pattern: "Sentence A. Actually, Sentence B" -> keep only Sentence B
        let pattern = #"(?:^|[\.!?]\s+)([^\.!?]+?)\.?\s+Actually,\s+([^\.!?]+)"#
        
        do {
            let regex = try NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
            
            let result = regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: "$2"
            )
            
            return result
        } catch {
            print("Failed to apply self-correction: \(error)")
            return text
        }
    }
    
    /// Final cleanup: capitalization, spacing, and punctuation
    private func cleanupSentences(_ text: String) -> String {
        var result = text
        
        // Remove multiple spaces
        result = result.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        
        // Remove spaces before punctuation
        result = result.replacingOccurrences(
            of: #"\s+([,.!?;:])"#,
            with: "$1",
            options: .regularExpression
        )
        
        // Ensure space after punctuation
        result = result.replacingOccurrences(
            of: #"([,.!?;:])([^\s\n])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        
        // Capitalize first letter of sentences if option enabled
        if options.automaticCapitalization {
            result = capitalizeSentences(result)
        }
        
        // Remove trailing commas and extra spaces
        result = result.replacingOccurrences(
            of: #",\s*$"#,
            with: "",
            options: .regularExpression
        )
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Capitalizes the first letter of each sentence
    private func capitalizeSentences(_ text: String) -> String {
        let pattern = #"(^|[\.!?]\s+)([a-z])"#
        
        do {
            let regex = try NSRegularExpression(
                pattern: pattern,
                options: []
            )
            
            var result = text
            let matches = regex.matches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: text.utf16.count)
            )
            
            // Process matches in reverse order to maintain indices
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3 else { continue }
                
                let fullRange = match.range(at: 0)
                let prefixRange = match.range(at: 1)
                let letterRange = match.range(at: 2)
                
                guard let fullSwiftRange = Range(fullRange, in: text),
                      let letterSwiftRange = Range(letterRange, in: text) else {
                    continue
                }
                
                let prefix = prefixRange.length > 0 ? String(text[Range(prefixRange, in: text)!]) : ""
                let uppercasedLetter = String(text[letterSwiftRange]).uppercased()
                
                result.replaceSubrange(fullSwiftRange, with: prefix + uppercasedLetter)
            }
            
            return result
        } catch {
            print("Failed to capitalize sentences: \(error)")
            return text
        }
    }
    
    /// Strips surrounding quotes from text if present
    private func stripSurroundingQuotes(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if text starts and ends with matching quotes
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            // Remove first and last character (the quotes)
            let startIndex = trimmed.index(after: trimmed.startIndex)
            let endIndex = trimmed.index(before: trimmed.endIndex)
            return String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return trimmed
    }
    
    // MARK: - Word Replacement Methods
    
    /// Load word replacements from UserDefaults
    private func loadWordReplacements() {
        if let data = UserDefaults.standard.data(forKey: "WordReplacements"),
           let replacements = try? JSONDecoder().decode([String: String].self, from: data) {
            wordReplacements = replacements
        } else {
            // Initialize with some common transcription errors
            wordReplacements = [
                "near chat": "Ner chat",
                "far away": "faraway", 
                "alright": "all right",
                "gonna": "going to",
                "wanna": "want to"
            ]
            saveWordReplacements()
        }
    }
    
    /// Save word replacements to UserDefaults
    private func saveWordReplacements() {
        if let data = try? JSONEncoder().encode(wordReplacements) {
            UserDefaults.standard.set(data, forKey: "WordReplacements")
        }
    }
    
    /// Apply word replacements to text using case-insensitive matching
    private func applyWordReplacements(_ text: String) -> String {
        var result = text
        
        for (searchTerm, replacement) in wordReplacements {
            // Create regex pattern for word boundaries (case-insensitive)
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: searchTerm))\\b"
            
            do {
                let regex = try NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                )
                
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: replacement
                )
            } catch {
                print("Failed to create regex for word replacement: \(searchTerm)")
            }
        }
        
        return result
    }
    
    /// Get current word replacements
    func getWordReplacements() -> [String: String] {
        return wordReplacements
    }
    
    /// Add or update a word replacement
    func addWordReplacement(searchTerm: String, replacement: String) {
        let trimmedSearch = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedSearch.isEmpty && !trimmedReplacement.isEmpty else { return }
        
        wordReplacements[trimmedSearch] = trimmedReplacement
        saveWordReplacements()
    }
    
    /// Remove a word replacement
    func removeWordReplacement(searchTerm: String) {
        let trimmedSearch = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        wordReplacements.removeValue(forKey: trimmedSearch)
        saveWordReplacements()
    }
    
    /// Clear all word replacements
    func clearWordReplacements() {
        wordReplacements.removeAll()
        saveWordReplacements()
    }
    
    /// Apply intelligent word replacements using GPT for fuzzy matching
    /// This method sends the word replacement dictionary to GPT and asks it to find and fix similar words
    func applyIntelligentWordReplacements(_ text: String) async throws -> String {
        // Check if we have word replacements and Azure OpenAI is configured
        guard !wordReplacements.isEmpty,
              let config = AzureOpenAIConfig.fromEnvironment() else {
            // Fall back to regular word replacements
            return applyWordReplacements(text)
        }
        
        // Create a prompt that includes our word replacement dictionary
        let replacementList = wordReplacements.map { "'\($0.key)' should be '\($0.value)'" }.joined(separator: ", ")
        
        let systemPrompt = """
        You are an AI assistant that fixes transcription errors in speech-to-text output. You have been given a list of known word replacements that should be applied when you find words that sound similar or are commonly misheard.

        Known replacements: \(replacementList)

        Your task:
        1. Look for words in the text that sound similar to the "search terms" in the replacement list
        2. Replace them with the correct words from the replacement list
        3. Use fuzzy matching - if you hear "ner chat" it should become "near chat"
        4. Be intelligent about partial matches and phonetic similarities
        5. Only make replacements when you're confident the original word is incorrect
        6. Preserve the original text structure, capitalization, and punctuation
        7. Don't make any other changes to the text

        Return only the corrected text with no explanations.
        """
        
        // Create API request URL
        let requestURL: String
        if config.endpoint.contains("?api-version=") {
            requestURL = config.endpoint
        } else {
            requestURL = "\(config.endpoint)openai/deployments/\(config.deploymentName)/chat/completions?api-version=\(config.apiVersion)"
        }
        
        // Create request body
        let requestBody = AzureOpenAIRequest(
            messages: [
                AzureOpenAIRequest.Message(role: "system", content: systemPrompt),
                AzureOpenAIRequest.Message(role: "user", content: text)
            ],
            temperature: 0.1, // Low temperature for consistent corrections
            maxTokens: 1000
        )
        
        // Encode request
        let jsonData = try JSONEncoder().encode(requestBody)
        
        // Create URLRequest
        var request = URLRequest(url: URL(string: requestURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(config.apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TranscriptCleaner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TranscriptCleaner", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorString)"])
        }
        
        // Decode response
        let apiResponse = try JSONDecoder().decode(AzureOpenAIResponse.self, from: data)
        
        // Extract corrected text
        guard let content = apiResponse.choices.first?.message.content else {
            throw NSError(domain: "TranscriptCleaner", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content in response"])
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Additional Azure OpenAI-based text refinement capabilities
extension TranscriptCleaner {
    /// Azure OpenAI configuration
    struct AzureOpenAIConfig {
        var endpoint: String
        var deploymentName: String 
        var apiVersion: String
        var apiKey: String
        
        /// Initialize with environment variables
        static func fromEnvironment() -> AzureOpenAIConfig? {
            // Use Azure OpenAI configuration from UserDefaults
            let endpoint = UserDefaults.standard.string(forKey: "AzureOpenAIEndpoint") ?? ""
            let deploymentName = UserDefaults.standard.string(forKey: "AzureOpenAIDeployment") ?? ""
            let apiVersion = UserDefaults.standard.string(forKey: "AzureOpenAIAPIVersion") ?? ""
            let apiKey = UserDefaults.standard.string(forKey: "AzureOpenAIAPIKey") ?? ""
            guard !endpoint.isEmpty, !deploymentName.isEmpty, !apiVersion.isEmpty, !apiKey.isEmpty else {
                print("❌ Azure OpenAI configuration incomplete in user preferences")
                print("📝 To use Azure OpenAI enhancement, please configure:")
                print("   • Azure OpenAI API Key", apiKey.isEmpty ? "(not set)" : "")
                print("   • Azure OpenAI Endpoint", endpoint.isEmpty ? "(not set)" : "")
                print("   • Azure OpenAI Deployment", deploymentName.isEmpty ? "(not set)" : "")
                print("   • Azure OpenAI API Version", apiVersion.isEmpty ? "(not set)" : "")
                print("   Open JustWhisper Preferences → Azure OpenAI API section")

                return nil
            }

            print("Azure OpenAI configuration found successfully")
            print("Using deployment: \(deploymentName)")
            print("Using API version: \(apiVersion)")
            
            return AzureOpenAIConfig(
                endpoint: endpoint,
                deploymentName: deploymentName,
                apiVersion: apiVersion,
                apiKey: apiKey
            )
        }
    }
    
    /// Structure for the Azure OpenAI API request 
    struct AzureOpenAIRequest: Codable {
        let messages: [Message]
        let temperature: Float
        let maxTokens: Int
        
        struct Message: Codable {
            let role: String
            let content: String
            
            enum CodingKeys: String, CodingKey {
                case role, content
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case messages, temperature
            case maxTokens = "max_tokens"
        }
    }
    
    /// Structure for the Azure OpenAI API response
    struct AzureOpenAIResponse: Codable {
        let id: String?
        let choices: [Choice]
        
        struct Choice: Codable {
            let index: Int
            let message: AzureOpenAIRequest.Message
        }
    }
    
    /// Use Azure OpenAI to enhance the transcript
    /// - Parameter text: The raw transcript text
    /// - Returns: Enhanced and cleaned text
    func enhanceWithAzureOpenAI(_ text: String) async throws -> String {
        // Check if Azure OpenAI configuration is available
        guard let config = AzureOpenAIConfig.fromEnvironment() else {
            print("Azure OpenAI configuration not found, using local processing")
            return cleanTranscript(text)
        }
        
        // Create system prompt with instructions
        let systemPrompt = """
        You are an AI assistant that improves transcribed speech. Follow these rules:
        1. Remove filler words (um, uh, like, etc.)
        2. Fix grammar and punctuation
        3. Maintain the speaker's original meaning and intent
        4. Format properly with paragraphs where appropriate
        5. Process any explicit formatting commands like "new line", "bullet point", etc.
        6. If the speaker corrects themselves, only keep the correction
        
        Return only the improved text with no explanations or other content.
        """
        
        // Create API request URL - use the endpoint directly as it's now correctly formatted in environment variables
        let requestURL: String
        if config.endpoint.contains("?api-version=") {
            // If endpoint already includes the API version, use it directly
            requestURL = config.endpoint
        } else {
            // Otherwise construct the URL
            requestURL = "\(config.endpoint)openai/deployments/\(config.deploymentName)/chat/completions?api-version=\(config.apiVersion)"
        }
        
        // Create request body
        let requestBody = AzureOpenAIRequest(
            messages: [
                AzureOpenAIRequest.Message(role: "system", content: systemPrompt),
                AzureOpenAIRequest.Message(role: "user", content: "Here is the transcribed speech to improve: \"\(text)\"")
            ],
            temperature: 0.3,
            maxTokens: 1000
        )
        
        // Encode request
        let jsonData = try JSONEncoder().encode(requestBody)
        
        // Create URLRequest
        var request = URLRequest(url: URL(string: requestURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(config.apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TranscriptCleaner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TranscriptCleaner", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorString)"])
        }
        
        // Decode response
        let apiResponse = try JSONDecoder().decode(AzureOpenAIResponse.self, from: data)
        
        // Extract cleaned text
        guard let content = apiResponse.choices.first?.message.content else {
            throw NSError(domain: "TranscriptCleaner", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content in response"])
        }
        
        // Strip surrounding quotes if present (Azure OpenAI sometimes wraps responses in quotes)
        let cleanedContent = stripSurroundingQuotes(content)
        
        return cleanedContent
    }
}


