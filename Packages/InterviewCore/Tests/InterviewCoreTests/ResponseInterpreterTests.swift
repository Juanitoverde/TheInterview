import XCTest
@testable import InterviewCore

final class ResponseInterpreterTests: XCTestCase {
    func testExtractsPositionFromNaturalReplies() {
        let cases: [(String, String)] = [
            ("I'm applying for a Technical Mechanic.", "Technical Mechanic"),
            ("I’m applying for a technical mechanic", "Technical Mechanic"),
            ("Um, I'm here for the senior software engineer position.", "Senior Software Engineer"),
            ("nurse", "Nurse"),
            ("I'm applying for an IT support specialist role", "IT Support Specialist"),
            ("Hi! I'm interviewing for the head of marketing role today.", "Head of Marketing"),
            ("The position is Registered Nurse, thank you.", "Registered Nurse"),
            ("Yes, I am here to interview for HVAC technician", "HVAC Technician"),
            ("Data analyst please", "Data Analyst"),
            ("I'm a welder", "Welder"),
        ]
        for (reply, expected) in cases {
            XCTAssertEqual(ResponseInterpreter.extractPosition(from: reply), expected, reply)
        }
    }

    func testKeepsRecogniserCapitalisation() {
        XCTAssertEqual(ResponseInterpreter.extractPosition(from: "I'm applying for an iOS Developer role"), "iOS Developer")
        XCTAssertEqual(ResponseInterpreter.extractPosition(from: "applying for a DevOps engineer"), "DevOps Engineer")
    }

    func testRejectsNonAnswers() {
        for reply in ["", "   ", "Sorry?", "what", "I don't know", "pardon",
                      "well I was thinking that maybe I could tell you a really long story about my career first"] {
            XCTAssertNil(ResponseInterpreter.extractPosition(from: reply), reply)
        }
    }

    func testReadiness() {
        XCTAssertEqual(ResponseInterpreter.readiness(of: "Yes, I'm ready."), .ready)
        XCTAssertEqual(ResponseInterpreter.readiness(of: "Yeah let's do it"), .ready)
        XCTAssertEqual(ResponseInterpreter.readiness(of: "Sure."), .ready)
        XCTAssertEqual(ResponseInterpreter.readiness(of: "Not yet, give me a second"), .notReady)
        XCTAssertEqual(ResponseInterpreter.readiness(of: "I'm not ready"), .notReady)
        XCTAssertEqual(ResponseInterpreter.readiness(of: "No."), .notReady)
        XCTAssertEqual(ResponseInterpreter.readiness(of: "Hmm"), .unclear)
        XCTAssertEqual(ResponseInterpreter.readiness(of: ""), .unclear)
    }

    func testRepeatRequests() {
        XCTAssertTrue(ResponseInterpreter.isRepeatRequest("Could you repeat the question?"))
        XCTAssertTrue(ResponseInterpreter.isRepeatRequest("Sorry, can you say that again"))
        XCTAssertTrue(ResponseInterpreter.isRepeatRequest("I didn't catch that"))
        XCTAssertFalse(ResponseInterpreter.isRepeatRequest("I fixed the brakes and the customer was happy."))
        XCTAssertFalse(ResponseInterpreter.isRepeatRequest(""))
        // Long answers that happen to contain "repeat" are not requests.
        XCTAssertFalse(ResponseInterpreter.isRepeatRequest(
            "We had repeat customers because I always explained the repair clearly and followed up a week later to check everything was fine"))
    }

    func testStripsFinishCue() {
        let stripped = ResponseInterpreter.strippingFinishCue(from: "I replaced the fuel line. That's my answer.")
        XCTAssertTrue(stripped.hadCue)
        XCTAssertEqual(stripped.text, "I replaced the fuel line.")

        let curly = ResponseInterpreter.strippingFinishCue(from: "It went well, I’m done")
        XCTAssertTrue(curly.hadCue)
        XCTAssertEqual(curly.text, "It went well")

        let none = ResponseInterpreter.strippingFinishCue(from: "That's all there is to it, really")
        XCTAssertFalse(none.hadCue)
        XCTAssertEqual(none.text, "That's all there is to it, really")

        XCTAssertEqual(ResponseInterpreter.strippingFinishCue(from: "That's my answer").text, "")
    }

    func testAddressedName() {
        XCTAssertEqual(CandidateProfile(fullName: "Jane Rivera", formOfAddress: .ms).addressedName, "Ms. Rivera")
        XCTAssertEqual(CandidateProfile(fullName: "  Sam  ", formOfAddress: .mr).addressedName, "Mr. Sam")
        XCTAssertEqual(CandidateProfile(fullName: "Jane Rivera", formOfAddress: .firstName).addressedName, "Jane")
        XCTAssertNil(CandidateProfile(fullName: "", formOfAddress: .dr).addressedName)
    }

    func testLooseCategoryDecoding() throws {
        let decoded = try JSONDecoder().decode([QuestionCategory].self, from: Data(#"["Behavioral", "role-specific", "STAR", "wrap-up", "closing", "weird"]"#.utf8))
        XCTAssertEqual(decoded, [.behavioral, .technical, .behavioral, .general, .closing, .general])
    }
}
