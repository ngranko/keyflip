import Testing
@testable import Keyflip

@Test func unicodeChunksPreserveSurrogatesAndEveryCodeUnit() {
    let text = String(repeating: "abcdefghijklmno🦊", count: 200)
    let chunks = KeyboardOutput.chunkUnicode(text)
    #expect(chunks.flatMap { $0 } == Array(text.utf16))
    #expect(chunks.allSatisfy { $0.count <= 16 && !(0xD800...0xDBFF).contains($0.last!) })
}

@Test func oversizedKeyboardWritesAreRejectedBeforePostingAnything() {
    #expect(!KeyboardOutput.replace(deleting: 4097, with: ""))
    #expect(!KeyboardOutput.replace(deleting: 1, with: String(repeating: "x", count: 4097)))
    #expect(!KeyboardOutput.replace(deleting: -1, with: "x"))
}
