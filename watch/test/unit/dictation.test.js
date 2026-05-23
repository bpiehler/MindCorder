import * as dictation from "../../src/embeddedjs/dictation.js";

describe("Dictation Errors (dictation.js)", () => {
    test("should map error values to types correctly", () => {
        assertEqual(dictation.getErrorType("No speech detected"), "no_speech");
        assertEqual(dictation.getErrorType("0"), "no_speech");
        
        assertEqual(dictation.getErrorType("Phone disconnected"), "connectivity");
        assertEqual(dictation.getErrorType("Network error"), "connectivity");
        
        assertEqual(dictation.getErrorType("User aborted session"), "aborted");
        assertEqual(dictation.getErrorType("System cancel"), "aborted");
        
        assertEqual(dictation.getErrorType("Rejected by user"), "rejected");
        assertEqual(dictation.getErrorType("Permission denied"), "rejected");
        
        assertEqual(dictation.getErrorType("Some internal database recognizer failure"), "internal_error");
        
        assertEqual(dictation.getErrorType(null), "unknown");
        assertEqual(dictation.getErrorType(undefined), "unknown");
    });

    test("should return correct error messages", () => {
        assertEqual(dictation.getErrorMessage("no_speech"), "No speech detected");
        assertEqual(dictation.getErrorMessage("connectivity"), "Phone not connected");
        assertEqual(dictation.getErrorMessage("aborted"), "Try again");
        assertEqual(dictation.getErrorMessage("rejected"), "");
        assertEqual(dictation.getErrorMessage("internal_error"), "Error, try again");
        assertEqual(dictation.getErrorMessage("unknown"), "Error, try again");
    });
});
