import AppIntents
import Foundation

struct CreateMeetingNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Meeting Notes"
    static var description = IntentDescription("Creates structured meeting notes using Private Cloud Compute when available, with an automatic on-device fallback.")
    static var openAppWhenRun = false

    @Parameter(title: "Transcript")
    var transcript: String

    @Parameter(title: "Meeting Title", default: "Meeting")
    var meetingTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create notes for \(\.$meetingTitle) from \(\.$transcript)")
    }

    @available(iOS 26, macOS 26, *)
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let notes = try await MeetingNotesService.generate(from: transcript, title: meetingTitle)
        return .result(value: notes)
    }
}
