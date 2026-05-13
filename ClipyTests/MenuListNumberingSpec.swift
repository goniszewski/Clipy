import Quick
import Nimble
@testable import Clipy

class MenuListNumberingSpec: QuickSpec {
    override class func spec() {

        describe("Menu list numbering") {

            it("keeps the tenth one-based display number while wrapping only the shortcut to zero") {
                expect(MenuListNumbering.nextDisplayNumber(after: 9)) == 10
                expect(MenuListNumbering.keyEquivalent(forDisplayNumber: 10, firstIndex: 1)) == "0"
            }

            it("does not wrap one-based display numbers after the tenth visible item") {
                expect(MenuListNumbering.nextDisplayNumber(after: 10)) == 11
                expect(MenuListNumbering.keyEquivalent(forDisplayNumber: 11, firstIndex: 1)).to(beNil())
            }

            it("keeps zero-started shortcuts mapped directly for the first ten visible items") {
                expect(MenuListNumbering.keyEquivalent(forDisplayNumber: 0, firstIndex: 0)) == "0"
                expect(MenuListNumbering.keyEquivalent(forDisplayNumber: 9, firstIndex: 0)) == "9"
                expect(MenuListNumbering.keyEquivalent(forDisplayNumber: 10, firstIndex: 0)).to(beNil())
            }

        }

    }
}
