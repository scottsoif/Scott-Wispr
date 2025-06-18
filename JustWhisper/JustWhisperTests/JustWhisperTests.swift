//
//  JustWhisperTests.swift
//  JustWhisperTests
//
//  Created by Scott Soifer on 6/16/25.
//

import XCTest
@testable import JustWhisper

class JustWhisperTests: XCTestCase {
    
    var transcriptCleaner: TranscriptCleaner!
    
    override func setUp() {
        super.setUp()
        transcriptCleaner = TranscriptCleaner()
    }
    
    override func tearDown() {
        transcriptCleaner = nil
        super.tearDown()
    }
    
    // MARK: - Basic Text Cleaning Tests
    
    func testBasicTextCleaning() {
        let input = "  Hello world  "
        let expected = "Hello world"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertEqual(result, expected, "Should trim whitespace")
    }
    
    func testEmptyString() {
        let input = ""
        let expected = ""
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertEqual(result, expected, "Should handle empty string")
    }
    
    func testWhitespaceOnlyString() {
        let input = "   \n\t  "
        let expected = ""
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertEqual(result, expected, "Should handle whitespace-only string")
    }
    
    // MARK: - Filler Word Removal Tests
    
    func testFillerWordRemoval() {
        let input = "Um, hello there, uh, how are you doing, like, today?"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertFalse(result.lowercased().contains("um"), "Should remove 'um'")
        XCTAssertFalse(result.lowercased().contains("uh"), "Should remove 'uh'")
        XCTAssertFalse(result.lowercased().contains("like"), "Should remove 'like'")
        XCTAssertTrue(result.contains("hello"), "Should preserve meaningful words")
    }
    
    func testFillerWordsWithWordBoundaries() {
        let input = "I like hiking unlike some people"
        let result = transcriptCleaner.cleanTranscript(input)
        // "like" should be removed as standalone word, but not in "unlike"
        XCTAssertTrue(result.contains("unlike"), "Should preserve 'unlike'")
        XCTAssertFalse(result.contains("I  hiking"), "Should remove standalone 'like'")
    }
    
    func testCaseInsensitiveFillerWords() {
        let input = "Um, YEAH, Basically this is good"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertFalse(result.lowercased().contains("um"), "Should remove lowercase 'um'")
        XCTAssertFalse(result.lowercased().contains("yeah"), "Should remove uppercase 'YEAH'")
        XCTAssertFalse(result.lowercased().contains("basically"), "Should remove mixed case 'Basically'")
    }
    
    // MARK: - Command Processing Tests
    
    func testNewLineCommands() {
        let input = "First line new line Second line"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("\n"), "Should convert 'new line' to newline character")
        XCTAssertTrue(result.contains("First line\nSecond line"), "Should have proper newline placement")
    }
    
    func testBulletPointCommands() {
        let input = "First item bullet point Second item"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("•"), "Should convert 'bullet point' to bullet character")
    }
    
    func testQuoteCommands() {
        let input = "He said quote hello world end quote yesterday"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("hello world"), "Should extract quoted content")
        XCTAssertFalse(result.contains("quote"), "Should remove 'quote' command")
        XCTAssertFalse(result.contains("end quote"), "Should remove 'end quote' command")
    }
    
    func testPunctuationCommands() {
        let input = "Hello period How are you question mark"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("."), "Should convert 'period' to '.'")
        XCTAssertTrue(result.contains("?"), "Should convert 'question mark' to '?'")
    }
    
    func testAllCapsCommands() {
        let input = "This is all caps important text end caps normal text"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("IMPORTANT TEXT"), "Should convert text to uppercase")
        XCTAssertTrue(result.contains("normal text"), "Should preserve normal text case")
    }
    
    func testCapitalizationCommands() {
        let input = "cap next word is important"
        let result = transcriptCleaner.cleanTranscript(input)
        // The cap command should capitalize the next word
        XCTAssertTrue(result.contains("Next") || result.contains("Word"), "Should capitalize word after 'cap'")
    }
    
    // MARK: - Self-Correction Tests
    
    func testSelfCorrectionWithActually() {
        let input = "I think it's red. Actually, it's blue and nice"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("blue"), "Should keep corrected content")
        XCTAssertFalse(result.contains("red"), "Should remove incorrect content")
        XCTAssertFalse(result.contains("Actually"), "Should remove 'Actually' marker")
    }
    
    func testMultipleSelfCorrections() {
        let input = "First wrong. Actually, first right. Second wrong. Actually, second right"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("first right"), "Should keep first correction")
        XCTAssertTrue(result.contains("second right"), "Should keep second correction")
        XCTAssertFalse(result.contains("wrong"), "Should remove all incorrect content")
    }
    
    // MARK: - Sentence Cleanup Tests
    
    func testMultipleSpaceRemoval() {
        let input = "Hello    world     there"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertFalse(result.contains("  "), "Should remove multiple spaces")
        XCTAssertEqual(result.components(separatedBy: " ").count, 3, "Should have exactly 3 words")
    }
    
    func testPunctuationSpacing() {
        let input = "Hello , world . How are you ?"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("Hello,"), "Should remove space before comma")
        XCTAssertTrue(result.contains("world."), "Should remove space before period")
        XCTAssertTrue(result.contains("you?"), "Should remove space before question mark")
    }
    
    func testSpaceAfterPunctuation() {
        let input = "Hello,world.How are you?Fine"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("Hello, world"), "Should add space after comma")
        XCTAssertTrue(result.contains("world. How"), "Should add space after period")
        XCTAssertTrue(result.contains("you? Fine"), "Should add space after question mark")
    }
    
    func testSentenceCapitalization() {
        let input = "hello world. how are you? fine thanks."
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.hasPrefix("Hello"), "Should capitalize first word")
        XCTAssertTrue(result.contains(". How"), "Should capitalize after period")
        XCTAssertTrue(result.contains("? Fine"), "Should capitalize after question mark")
    }
    
    func testTrailingCommaRemoval() {
        let input = "Hello world,"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertFalse(result.hasSuffix(","), "Should remove trailing comma")
        XCTAssertTrue(result.hasSuffix("world"), "Should end with the word")
    }
    
    // MARK: - Complex Integration Tests
    
    func testComplexTranscript() {
        let input = "Um, hello there period Actually, uh, good morning period How are you doing question mark"
        let result = transcriptCleaner.cleanTranscript(input)
        
        // Should remove filler words
        XCTAssertFalse(result.lowercased().contains("um"), "Should remove 'um'")
        XCTAssertFalse(result.lowercased().contains("uh"), "Should remove 'uh'")
        
        // Should process commands
        XCTAssertTrue(result.contains("."), "Should convert 'period' to '.'")
        XCTAssertTrue(result.contains("?"), "Should convert 'question mark' to '?'")
        
        // Should apply self-correction
        XCTAssertFalse(result.contains("hello there"), "Should remove incorrect greeting")
        XCTAssertTrue(result.contains("good morning"), "Should keep corrected greeting")
        
        // Should have proper capitalization
        XCTAssertTrue(result.hasPrefix("Good"), "Should capitalize first word")
    }
    
    func testComplexCommandsWithFillers() {
        let input = "Um, first item bullet point uh, second item bullet point like, third item"
        let result = transcriptCleaner.cleanTranscript(input)
        
        // Should remove fillers
        XCTAssertFalse(result.lowercased().contains("um"), "Should remove 'um'")
        XCTAssertFalse(result.lowercased().contains("uh"), "Should remove 'uh'")
        XCTAssertFalse(result.lowercased().contains("like"), "Should remove 'like'")
        
        // Should create bullet points
        let bulletCount = result.components(separatedBy: "•").count - 1
        XCTAssertEqual(bulletCount, 2, "Should create 2 bullet points")
    }
    
    // MARK: - Edge Cases
    
    func testOnlyFillerWords() {
        let input = "um uh like yeah"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.isEmpty || result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, 
                      "Should result in empty or whitespace-only string when input contains only filler words")
    }
    
    func testNestedQuotes() {
        let input = "He said quote she said hello end quote to me"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("she said hello"), "Should handle nested quotes correctly")
    }
    
    func testMalformedCommands() {
        let input = "Hello quote unclosed quote and bullet incomplete"
        let result = transcriptCleaner.cleanTranscript(input)
        // Should handle malformed commands gracefully without crashing
        XCTAssertNotNil(result, "Should handle malformed commands without crashing")
        XCTAssertTrue(result.contains("Hello"), "Should preserve valid content")
    }
    
    func testSpecialCharacters() {
        let input = "Hello@world.com and #hashtag"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("@"), "Should preserve @ character")
        XCTAssertTrue(result.contains("#"), "Should preserve # character")
        XCTAssertTrue(result.contains(".com"), "Should preserve domain extensions")
    }
    
    func testUnicodeCharacters() {
        let input = "Café résumé naïve"
        let result = transcriptCleaner.cleanTranscript(input)
        XCTAssertTrue(result.contains("é"), "Should preserve unicode characters")
        XCTAssertTrue(result.contains("ï"), "Should preserve accented characters")
    }
}
