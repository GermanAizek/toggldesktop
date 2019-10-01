//
//  TimeEntryTouchbar.swift
//  TogglDesktop
//
//  Created by Nghia Tran on 10/1/19.
//  Copyright © 2019 Alari. All rights reserved.
//

import Foundation

@available(OSX 10.12.2, *)
final class TimeEntryTouchBar: NSObject {

    // MARK: Variables

    private lazy var touchBar = NSTouchBar()

    // MARK: Init

    override init() {
        super.init()
        initCommon()
        setup()
    }
}

@available(OSX 10.12.2, *)
extension TimeEntryTouchBar {

    fileprivate func initCommon() {

    }

    fileprivate func setup() {
        touchBar.delegate = self
        touchBar.customizationIdentifier = .timeEntry
        touchBar.defaultItemIdentifiers = [.timeEntryItem, .flexibleSpace, .runningTimeEntry, .startStopItem]
    }
}

// MARK: NSTouchBarDelegate

@available(OSX 10.12.2, *)
extension TimeEntryTouchBar: NSTouchBarDelegate {

}

@available(OSX 10.12.2, *)
extension NSTouchBar.CustomizationIdentifier {
    static let timeEntry = NSTouchBar.CustomizationIdentifier("com.toggl.toggldesktop.timeentrytouchbar")
}

@available(OSX 10.12.2, *)
extension NSTouchBarItem.Identifier {

    static let timeEntryItem = NSTouchBarItem.Identifier("com.toggl.toggldesktop.timeentrytouchbar.timeentryitems")
    static let runningTimeEntry = NSTouchBarItem.Identifier("com.toggl.toggldesktop.timeentrytouchbar.runningtimeentry")
    static let startStopItem = NSTouchBarItem.Identifier("com.toggl.toggldesktop.timeentrytouchbar.startstopbutton")
}