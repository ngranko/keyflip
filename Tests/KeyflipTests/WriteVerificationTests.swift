import Foundation
import Testing
@testable import Keyflip

@Test func confirmZenAddressBarRewriteWithSelectedAutocomplete() {
    let result = WriteVerification.classify(
        value: "test.example/path", selection: NSRange(location: 4, length: 13),
        before: "еуые", range: NSRange(location: 0, length: 4), wrote: "test", over: "еуые"
    )
    #expect(result == .completed)
}

@Test func rejectExtraAddressBarTextWithoutSelectedAutocomplete() {
    let value = "test.example/path"
    let result = WriteVerification.classify(
        value: value, selection: NSRange(location: 17, length: 0),
        before: "еуые", range: NSRange(location: 0, length: 4), wrote: "test", over: "еуые"
    )
    #expect(result == .mangled(value))
}

@Test func rejectInsertedConversionThatLeavesTheOriginal() {
    let result = WriteVerification.classify(
        value: "testеуые", selection: NSRange(location: 4, length: 0),
        before: "еуые", range: NSRange(location: 0, length: 4), wrote: "test", over: "еуые"
    )
    #expect(result == .mangled("testеуые"))
}
