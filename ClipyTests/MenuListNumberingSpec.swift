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

        describe("History menu layout") {

            it("does not plan a submenu when every visible clip fits inline") {
                expect(HistoryMenuLayout.firstSubmenuIndex(existingItemCount: 2, inlineCapacity: 10, visibleClipCount: 3)).to(beNil())
            }

            it("places the first submenu after the label and inline clips") {
                expect(HistoryMenuLayout.firstSubmenuIndex(existingItemCount: 2, inlineCapacity: 3, visibleClipCount: 8)) == 6
            }

            it("places the first submenu immediately after the label when inline clips are disabled") {
                expect(HistoryMenuLayout.firstSubmenuIndex(existingItemCount: 2, inlineCapacity: 0, visibleClipCount: 8)) == 3
            }

            it("groups overflow clips into stable submenu buckets") {
                expect(HistoryMenuLayout.placement(forClipIndex: 2, inlineCapacity: 3, itemsPerSubmenu: 4)) == .inline
                expect(HistoryMenuLayout.placement(forClipIndex: 3, inlineCapacity: 3, itemsPerSubmenu: 4)) == .submenu(groupIndex: 0, itemIndex: 0)
                expect(HistoryMenuLayout.placement(forClipIndex: 6, inlineCapacity: 3, itemsPerSubmenu: 4)) == .submenu(groupIndex: 0, itemIndex: 3)
                expect(HistoryMenuLayout.placement(forClipIndex: 7, inlineCapacity: 3, itemsPerSubmenu: 4)) == .submenu(groupIndex: 1, itemIndex: 0)
            }

        }

    }
}
