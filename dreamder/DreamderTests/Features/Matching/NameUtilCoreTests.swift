import Testing
@testable import Dreamder

@Suite("NameUtilCore")
struct NameUtilCoreTests {
    @Test func splitsCamelCaseIntoWords() {
        #expect(NameUtilCore.splitNameIntoWordList("IBase") == ["I", "Base"])
        #expect(NameUtilCore.splitNameIntoWordList("OrderIndex") == ["Order", "Index"])
        #expect(NameUtilCore.splitNameIntoWordList("orderIndex") == ["order", "Index"])
        #expect(NameUtilCore.splitNameIntoWordList("Order_Index") == ["Order", "Index"])
        #expect(NameUtilCore.splitNameIntoWordList("ORDER_INDEX") == ["ORDER", "INDEX"])
        #expect(NameUtilCore.splitNameIntoWordList("ggJ") == ["gg", "J"])
    }

    @Test func splitsAllCapsAcronymFromFollowingWord() {
        #expect(NameUtilCore.splitNameIntoWordList("HTTPServer") == ["HTTP", "Server"])
        #expect(NameUtilCore.splitNameIntoWordList("XMLHttpRequest") == ["XML", "Http", "Request"])
        #expect(NameUtilCore.splitNameIntoWordList("parseHTML") == ["parse", "HTML"])
    }

    @Test func digitsFormSeparateWords() {
        #expect(NameUtilCore.splitNameIntoWordList("foo2bar") == ["foo", "2", "bar"])
        #expect(NameUtilCore.splitNameIntoWordList("Vec3Add") == ["Vec", "3", "Add"])
    }

    @Test func emptyAndUnderscoreOnlyNamesHaveNoWords() {
        #expect(NameUtilCore.splitNameIntoWordList("").isEmpty)
        #expect(NameUtilCore.splitNameIntoWordList("__").isEmpty)
    }

    @Test func splitsChineseIdeographsIndividually() {
        #expect(
            NameUtilCore.splitNameIntoWordList("测试打补丁2")
                == ["测", "试", "打", "补", "丁", "2"]
        )
    }

    @Test func splitsJapaneseAtScriptBoundaries() {
        #expect(
            NameUtilCore.splitNameIntoWordList("ローマ由来のアルファベット（ラテン文字）を用いて日本語を表記することもでき、日本ではローマ字と呼ばれる")
                == ["ローマ", "由", "来", "の", "アルファベット", "（", "ラテン", "文", "字", "）", "を", "用", "いて", "日", "本", "語",
                    "を", "表", "記", "することもでき", "、", "日", "本", "では", "ローマ", "字", "と", "呼", "ばれる"]
        )
        #expect(
            NameUtilCore.splitNameIntoWordList("近代では日本人が漢語を造語する例もあり、英語のphilosophy、ドイツ語のPhilosophieを指す用語")
                == ["近", "代", "では", "日", "本", "人", "が", "漢", "語", "を", "造", "語", "する", "例", "もあり", "、", "英", "語",
                    "の", "philosophy", "、", "ドイツ", "語", "の", "Philosophie", "を", "指", "す", "用", "語"]
        )
    }

    @Test func splitsEmojiAsSurrogatePairs() {
        #expect(
            NameUtilCore.splitNameIntoWordList("\u{1F92B} \u{1F52B}\u{1F9D2}")
                == ["\u{1F92B}", " ", "\u{1F52B}", "\u{1F9D2}"]
        )
    }

    @Test func wordStartInsideIdeographs() {
        let text = Array("测试打补丁".utf16)
        #expect(NameUtilCore.isWordStart(text, 0))
        #expect(NameUtilCore.isWordStart(text, 2))
    }

    @Test func wordStartRules() {
        let text = Array("HTTPServer_fooBar2x".utf16)
        let starts = text.indices.filter { NameUtilCore.isWordStart(text, $0) }
        #expect(starts == [0, 4, 11, 14, 17])
    }

    @Test func allCapsMiddleLettersAreNotWordStarts() {
        let text = Array("HTTPServer".utf16)
        #expect(NameUtilCore.isWordStart(text, 0))
        #expect(!NameUtilCore.isWordStart(text, 1))
        #expect(!NameUtilCore.isWordStart(text, 2))
        #expect(!NameUtilCore.isWordStart(text, 3))
        #expect(NameUtilCore.isWordStart(text, 4))
        #expect(!NameUtilCore.isWordStart(text, 5))
    }

    @Test func trailingAllCapsLetterIsNotAWordStart() {
        let text = Array("ABC".utf16)
        #expect(NameUtilCore.isWordStart(text, 0))
        #expect(!NameUtilCore.isWordStart(text, 1))
        #expect(!NameUtilCore.isWordStart(text, 2))
    }

    @Test func nextWordAdvancesPastNonLetters() {
        let text = Array("a-b".utf16)
        #expect(NameUtilCore.nextWord(text, 0) == 1)
        #expect(NameUtilCore.nextWord(text, 1) == 2)
        #expect(NameUtilCore.nextWord(text, 2) == 3)
    }
}

@Suite("NameUtilCore kana boundaries")
struct NameUtilCoreKanaTests {
    private func isWordStart(_ text: String, _ index: Int) -> Bool {
        NameUtilCore.isWordStart(Array(text.utf16), index)
    }

    @Test func hiraganaToKatakanaAndBackIsABreak() {
        #expect(isWordStart("あア", 1))
        #expect(isWordStart("アあ", 1))
    }

    @Test func sameScriptKanaDoesNotBreak() {
        #expect(!isWordStart("ああ", 1))
        #expect(!isWordStart("ｱｲ", 1))
    }

    @Test func prolongedSoundMarkBelongsToThePrecedingKatakana() {
        #expect(!isWordStart("カー", 1))
        #expect(NameUtilCore.splitNameIntoWordList("カー") == ["カー"])
    }

    @Test func halfwidthKatakanaAfterHiraganaIsABreak() {
        #expect(isWordStart("あｱ", 1))
        #expect(isWordStart("ｱあ", 1))
    }

    @Test func kanaNextToLatinOrHanIsABreak() {
        #expect(isWordStart("aカ", 1))
        #expect(isWordStart("日ア", 1))
    }

    @Test func kanaAfterDigitIsNotAKanaBreak() {
        #expect(!isWordStart("1あ", 1))
    }

    @Test func splitsAtHiraganaKatakanaBoundariesAndAroundDigits() {
        #expect(NameUtilCore.splitNameIntoWordList("ひらがなカタカナ") == ["ひらがな", "カタカナ"])
        #expect(NameUtilCore.splitNameIntoWordList("カタカナ1ひらがな") == ["カタカナ", "1", "ひらがな"])
    }
}

@Suite("MatchingCharacter classification")
struct MatchingCharacterTests {
    @Test(arguments: [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0xA0, 0x1680, 0x2028, 0x2029, 0x3000])
    func whitespaceCodePoints(codePoint: Int) {
        #expect(MatchingCharacter.isWhitespace(UInt32(codePoint)))
    }

    @Test(arguments: [0x08, 0x0E, 0x41, 0x5F, 0x85, 0x200B, 0xD800, 0x30C2])
    func nonWhitespaceCodePoints(codePoint: Int) {
        #expect(!MatchingCharacter.isWhitespace(UInt32(codePoint)))
    }

    @Test(arguments: [0x0301, 0x20DD, 0x0903, 0x3099])
    func markCodePoints(codePoint: Int) {
        #expect(MatchingCharacter.isMark(UInt32(codePoint)))
    }

    @Test(arguments: [0x61, 0x31, 0x30AB, 0xD800])
    func nonMarkCodePoints(codePoint: Int) {
        #expect(!MatchingCharacter.isMark(UInt32(codePoint)))
    }
}
