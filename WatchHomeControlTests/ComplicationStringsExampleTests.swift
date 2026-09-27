// ComplicationStringsExampleTests.swift
//
// Feature: tv-lamp-complication — example (unit) test for the complication's
// shared German strings.
//
// Validates Requirements 9.1, 9.2, 9.3.
//
// The Complication itself has no test target (the widget extension is a
// separate module with no linked test bundle), so this asserts the shared
// `Strings` values the extension consumes are non-empty and match the required
// German text; the extension's compiled `TVLampComplicationView`/`TVLampWidget`
// referencing these same constants is verified by a full build rather than a
// runtime test.

import Testing
@testable import WatchHomeControl_Watch_App

struct ComplicationStringsExampleTests {
    @Test("Req 9.1/9.3: the complication label is the non-empty German \"TV\"")
    func complicationLabelIsNonEmpty() {
        #expect(Strings.complicationLabel == "TV")
        #expect(!Strings.complicationLabel.isEmpty)
    }

    @Test("Req 9.2: the gallery display name is the German \"TV-Lampe\"")
    func complicationDisplayNameIsGerman() {
        #expect(Strings.complicationDisplayName == "TV-Lampe")
    }

    @Test("Req 9.2: the gallery description is non-empty German text")
    func complicationDescriptionIsNonEmpty() {
        #expect(!Strings.complicationDescription.isEmpty)
        #expect(Strings.complicationDescription.contains("TV-Lampe"))
    }
}
