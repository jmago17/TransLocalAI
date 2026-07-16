//
//  TranscriberTests.swift
//  TranscriberTests
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import Testing
@testable import Transcriber

struct TranscriberTests {

    @Test func importsSRTWithoutSequenceNumbersOrTimecodes() throws {
        let input = """
        1
        00:00:01,000 --> 00:00:03,000
        Welcome to Danobat.

        2
        00:00:04,000 --> 00:00:06,000
        Eneko owns the next action.
        """
        let output = try TranscriptFileParser.text(from: Data(input.utf8), extension: "srt")
        #expect(output == "Welcome to Danobat.\nEneko owns the next action.")
    }

    @Test func importsSegmentedJSON() throws {
        let input = #"{"segments":[{"text":"First"},{"text":"Second"}]}"#
        let output = try TranscriptFileParser.text(from: Data(input.utf8), extension: "json")
        #expect(output == "First\nSecond")
    }

}
